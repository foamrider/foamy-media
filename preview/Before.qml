import QtQuick
import Quickshell.Io
import ".." as Dev

// The dev (1.0) UI for the kit's --trio renders: the real 1.0 Panel with its
// MediaPopup fork, opened against the harness bar. For the playing states a
// fake MPRIS player (two for two-sources) runs on the harness's private
// D-Bus, with the same track, cover and position as preview/Preview.qml; it
// refuses any other bus and exits with the render. Offscreen there are no
// Wayland toplevels, so dev cannot see the YouTube web app: its two-sources
// view shows Spotify with the browser player present.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["playing", "two-sources", "not-running", "settings"]
  property string previewState: "playing"
  // The cover probe (ImageMagick) runs after the player appears.
  property int settleMs: 2500
  // 1.0 keeps its popup (id popup) inside Panel.qml, and the harness window
  // that replaces the fork's PanelWindow reparents it into the simulated
  // screen, so look it up in the scene by its owner once it exists.
  property Item found: old
  readonly property Item popup: found

  function findPopup(item, depth) {
    if (!item || depth > 8) return null
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      if (child && child.owner === old && child.borderSpec !== undefined) return child
      var deeper = findPopup(child, depth + 1)
      if (deeper) return deeper
    }
    return null
  }

  // Dev wraps its header (cover, title, the blurred backdrop) in
  // MultiEffect layers, which draw nothing under the harness's software
  // renderer. Turn those layers off so the shot shows dev's header content as
  // on a GPU (without the blur and rounded masks).
  function unlayer(item, depth) {
    if (!item || depth > 40) return
    if (item.layer && item.layer.enabled && item.layer.effect) item.layer.enabled = false
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) unlayer(kids[i], depth + 1)
  }
  Timer {
    interval: 200
    repeat: true
    running: preview.found !== old
    onTriggered: preview.unlayer(preview.found, 0)
  }

  Timer {
    interval: 50
    running: preview.found === old
    repeat: true
    onTriggered: {
      var top = preview
      while (top.parent) top = top.parent
      var popup = preview.findPopup(top, 0)
      if (!popup) return
      popup.anchorItem = preview.anchorItem
      preview.found = popup
    }
  }

  Dev.Panel {
    id: old
    bar: preview.bar
    width: 60
    height: 30
    settings: ({ id: "foamy.media", hideWhenClosed: false })
    Component.onCompleted: old.open()
  }
  onPreviewStateChanged: {
    if (previewState === "settings") old.openSettings(); else old.closeSettings()
    preview.startFixture()
  }
  Component.onCompleted: startFixture()

  function startFixture() {
    fixture.running = false
    if (previewState !== "playing" && previewState !== "two-sources") return
    var state = previewState
    Qt.callLater(function() {
      fixture.command = ["python3", "-I", "-c", preview.fixtureSource, state]
      fixture.running = true
    })
  }
  Process {
    id: fixture
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") console.log("fake MPRIS: " + text.trim()) }
  }
  // A static MPRIS fixture (python3-dbus), embedded so the dev copy the kit
  // renders (git archive of dev + this file) has it.
  readonly property string fixtureSource: "import os, sys, struct, zlib, math\nbus_address = os.environ.get(\"DBUS_SESSION_BUS_ADDRESS\", \"\")\nif not (bus_address.startswith(\"unix:path=/tmp/foamy-kit-\") and bus_address.endswith(\"/bus\")):\n    sys.exit(\"fake MPRIS: refusing to run outside the foamy-kit harness private bus\")\nimport dbus, dbus.service\nfrom dbus.mainloop.glib import DBusGMainLoop\nfrom gi.repository import GLib\n\nstate = sys.argv[1] if len(sys.argv) > 1 else \"playing\"\nruntime = os.environ.get(\"XDG_RUNTIME_DIR\", \"/tmp\")\ncover = os.path.join(runtime, \"foamy-media-cover.png\")\n\ndef png(path, size=256):\n    # The preview's mock cover: a #2b5876 -> #4e4376 gradient with a #f0a35e glow.\n    top, bottom, glow = (0x2b, 0x58, 0x76), (0x4e, 0x43, 0x76), (0xf0, 0xa3, 0x5e)\n    rows = bytearray()\n    for y in range(size):\n        rows.append(0)\n        t = y / (size - 1)\n        for x in range(size):\n            d = math.hypot(x - size / 2, y - size / 2) / (size / 2)\n            a = max(0.0, 1.0 - d)\n            for i in range(3):\n                base = top[i] + (bottom[i] - top[i]) * t\n                rows.append(int(round(base + (glow[i] - base) * a)))\n    def chunk(kind, data):\n        return struct.pack(\">I\", len(data)) + kind + data + struct.pack(\">I\", zlib.crc32(kind + data) & 0xffffffff)\n    with open(path, \"wb\") as f:\n        f.write(b\"\\x89PNG\\r\\n\\x1a\\n\" + chunk(b\"IHDR\", struct.pack(\">IIBBBBB\", size, size, 8, 2, 0, 0, 0))\n                + chunk(b\"IDAT\", zlib.compress(bytes(rows), 9)) + chunk(b\"IEND\", b\"\"))\n\nROOT, PLAYER, PROPS = \"org.mpris.MediaPlayer2\", \"org.mpris.MediaPlayer2.Player\", \"org.freedesktop.DBus.Properties\"\n\nclass Player(dbus.service.Object):\n    def __init__(self, bus, name, identity, entry, track):\n        self.bus_name = dbus.service.BusName(name, bus)\n        super().__init__(self.bus_name, \"/org/mpris/MediaPlayer2\")\n        self.root = {\"Identity\": identity, \"DesktopEntry\": entry, \"CanQuit\": False, \"CanRaise\": True,\n                     \"HasTrackList\": False, \"SupportedUriSchemes\": dbus.Array([], \"s\"), \"SupportedMimeTypes\": dbus.Array([], \"s\")}\n        meta = {\"mpris:trackid\": dbus.ObjectPath(\"/org/foamy/track/1\"), \"xesam:title\": track[\"title\"],\n                \"xesam:artist\": dbus.Array([track[\"artist\"]], \"s\"), \"mpris:length\": dbus.Int64(track[\"length\"] * 1000000)}\n        if track.get(\"album\"): meta[\"xesam:album\"] = track[\"album\"]\n        if track.get(\"art\"): meta[\"mpris:artUrl\"] = track[\"art\"]\n        if track.get(\"url\"): meta[\"xesam:url\"] = track[\"url\"]\n        self.player = {\"PlaybackStatus\": track[\"status\"], \"LoopStatus\": \"None\", \"Rate\": 1.0, \"Shuffle\": track.get(\"shuffle\", False),\n                       \"Metadata\": dbus.Dictionary(meta, signature=\"sv\"), \"Volume\": 0.65,\n                       \"Position\": dbus.Int64(track[\"position\"] * 1000000), \"MinimumRate\": 1.0, \"MaximumRate\": 1.0,\n                       \"CanGoNext\": True, \"CanGoPrevious\": True, \"CanPlay\": True, \"CanPause\": True, \"CanSeek\": True, \"CanControl\": True}\n    def table(self, interface):\n        return self.root if interface == ROOT else self.player\n    @dbus.service.method(PROPS, in_signature=\"ss\", out_signature=\"v\")\n    def Get(self, interface, prop):\n        return self.table(interface)[prop]\n    @dbus.service.method(PROPS, in_signature=\"s\", out_signature=\"a{sv}\")\n    def GetAll(self, interface):\n        return dbus.Dictionary(self.table(interface), signature=\"sv\")\n    @dbus.service.method(PROPS, in_signature=\"ssv\")\n    def Set(self, interface, prop, value):\n        pass  # a still picture: nothing changes\n    @dbus.service.signal(PROPS, signature=\"sa{sv}as\")\n    def PropertiesChanged(self, interface, changed, invalidated):\n        pass\n    @dbus.service.method(PLAYER)\n    def Next(self): pass\n    @dbus.service.method(PLAYER)\n    def Previous(self): pass\n    @dbus.service.method(PLAYER)\n    def Pause(self): pass\n    @dbus.service.method(PLAYER)\n    def PlayPause(self): pass\n    @dbus.service.method(PLAYER)\n    def Stop(self): pass\n    @dbus.service.method(PLAYER)\n    def Play(self): pass\n    @dbus.service.method(PLAYER, in_signature=\"x\")\n    def Seek(self, offset): pass\n    @dbus.service.method(PLAYER, in_signature=\"ox\")\n    def SetPosition(self, track, position): pass\n    @dbus.service.method(ROOT)\n    def Raise(self): pass\n\nDBusGMainLoop(set_as_default=True)\n\nplayers = []\nif state in (\"playing\", \"two-sources\"):\n    png(cover)\n    players.append(Player(dbus.SessionBus(private=True), \"org.mpris.MediaPlayer2.spotify\", \"Spotify\", \"spotify\", {\n        \"title\": \"A Quiet Morning\", \"artist\": \"Example Artist\", \"album\": \"Demo Album\", \"length\": 240, \"position\": 85,\n        \"status\": \"Playing\", \"shuffle\": True, \"art\": \"file://\" + cover}))\nif state == \"two-sources\":\n    players.append(Player(dbus.SessionBus(private=True), \"org.mpris.MediaPlayer2.vivaldi.instance1\", \"Vivaldi\", \"vivaldi-stable\", {\n        \"title\": \"Building a tiny synthesizer from scratch\", \"artist\": \"Sound Lab\", \"length\": 1124, \"position\": 431,\n        \"status\": \"Paused\", \"url\": \"https://www.youtube.com/watch?v=foamy\"}))\nparent = os.getppid()\ndef watch():\n    if os.getppid() != parent: loop.quit()\n    return True\nGLib.timeout_add(500, watch)\nGLib.timeout_add_seconds(120, lambda: loop.quit())\nloop = GLib.MainLoop()\nloop.run()\n"
}
