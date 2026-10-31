import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "harness"
import "plugin" as Media
import "plugin/kit"

// Foamy Media under a real host shell, offscreen: three bar instances (as on
// three monitors) sharing one MediaService and one leader, the lazy popup
// body, the single keyboard cursor, settings saving through the bar, the
// cover rules (no stale cover after a failed fetch), the equalizer and
// marquee gates, translations and RTL mirroring. No MPRIS player is
// reachable here, so the widget is in its "not running" state.
ShellRoot {
  id: shell
  readonly property string host: Quickshell.env("FOAMY_HOST")
  readonly property string lang: Quickshell.env("FOAMY_LANG") || "en"
  readonly property bool v45: host === "4.5"
  property int checks: 0
  property int failures: 0

  function check(ok, label) {
    checks++
    if (!ok) { failures++; console.log("FOAMY FAIL " + host + "/" + lang + " " + label) }
  }
  function eq(actual, expected, label) {
    check(actual === expected, label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
  }

  FloatingWindow {
    implicitWidth: 1920
    implicitHeight: 1080
    color: "black"
    ScreenSim { id: sim }
    Row {
      id: barRow
      y: 4
      x: 1200
      spacing: 40
      Repeater {
        id: panels
        model: 3
        Media.Panel {
          bar: mockBar
          moduleName: "foamy.media"
          settings: ({ id: "foamy.media", hideWhenClosed: false, extra: "kept" })
        }
      }
    }
    // Presentation pieces, fed directly.
    Media.Equalizer { id: equalizer; playing: true; animate: true }
    Media.MediaView { id: playerView; y: 120; width: 420; media: player }
    Media.BarContent {
      id: barContent
      y: 60
      label: "A title far too long to fit in the narrow slot it has been given here"
      maxLabelWidth: 80
      live: true
      playing: false
      showProgress: true
      progress: 0.5
    }
  }

  MockBar { id: mockBar; moduleName: "foamy.media" }
  // The 4.5 host: an inline save updates the widget's settings before it returns.
  QtObject {
    id: reflectingShell
    property var panel: null
    function updateEntryInline(id, settings) {
      mockBar.saved = mockBar.saved.concat([{ id: id, settings: settings }])
      var next = { id: id }
      for (var k in settings) next[k] = settings[k]
      panel.settings = next
      return true
    }
  }

  // A playing player for the cursor checks (MediaView reads only `media`).
  QtObject {
    id: player
    property var calls: []
    function log(name, value) { calls = calls.concat([name + (value === undefined ? "" : ":" + value)]) }
    readonly property QtObject bar: mockBar
    property bool opened: true
    property bool editingSettings: false
    property bool live: true
    property bool playing: true
    property string sourceKind: "spotify"
    property string sourceName: "Spotify"
    property string sourceIcon: ""
    property bool sourceOpen: true
    property bool spotifyOpen: true
    property bool youtubeOpen: true
    property bool anySourceOpen: true
    property bool spotifyPlaying: true
    property bool youtubePlaying: false
    property string trackTitle: "Title"
    property string trackArtist: "Artist"
    property string trackAlbum: ""
    property real trackLength: 200
    property real trackPosition: 50
    property bool canSeek: true
    property bool canGoPrevious: true
    property bool canGoNext: true
    property bool shuffleSupported: true
    property bool loopSupported: true
    property bool volumeSupported: true
    property real volume: 0.5
    property bool shuffleOn: false
    property string loopName: "off"
    property string artSource: ""
    property string artDominant: ""
    property real artLuma: 0
    property bool artBackground: true
    property int artIntensity: 55
    property bool showEqualizer: true
    property color spotifyGreen: "green"
    property color youtubeRed: "red"
    property color sourceBrandColor: "green"
    property var settings: ({})
    function playPause() { log("playPause") }
    function skipNext() { log("next") }
    function skipPrevious() { log("previous") }
    function seekTo(s) { log("seekTo", s) }
    function seekBy(s) { log("seekBy", s) }
    function setVolume(v) { log("volume", Math.round(v * 100)) }
    function toggleShuffle() { log("shuffle") }
    function cycleLoop() { log("loop") }
    function selectSource(k) { log("select", k) }
    function launch() { log("launch") }
    function openSettings() { log("settings") }
    function closeSettings() {}
    function close() { log("close") }
    function switchPanel(d) { log("switch", d) }
  }

  Component.onCompleted: Qt.callLater(stepOne)

  FoamyCursor { id: keys }
  function findKey(item, key) {
    if (!item) return null
    if (item.key === key && item.commitEdit !== undefined) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var hit = findKey(kids[i], key); if (hit) return hit }
    return null
  }
  function key(view, text) { keys.emitTextKey(view, text) }
  function findNamed(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var hit = findNamed(kids[i], name); if (hit) return hit }
    return null
  }

  function leaders() {
    var count = 0
    for (var i = 0; i < 3; i++) if (panels.itemAt(i).statusObject().leader) count++
    return count
  }

  function stepOne() {
    eq(leaders(), 1, "one leader across three bar instances")
    eq(panels.itemAt(0).member.members, 3, "three members")
    var first = panels.itemAt(0)
    eq(first.live, false, "no player offscreen")
    eq(first.popup.bodyItem, null, "popup body is lazy")
    eq(first.member.demanded, false, "no demand while closed")

    // Selection is shared by every bar.
    first.selectSource("spotify")
    Media.MediaService.selectedSource = "youtube"
    eq(panels.itemAt(2).sourceKind, "youtube", "source shared across bars")
    Media.MediaService.selectedSource = "spotify"

    // Cover rules (regression: a failed fetch kept the previous cover).
    var svc = Media.MediaService
    var a = "file:///nonexistent/foamy-media-a.png", b = "file:///nonexistent/foamy-media-b.png"
    svc.request(a); svc.artProbeDelay.stop()
    svc.applyArtProbe(a, "MEAN 336699\nART /tmp/a.png\n")
    eq(svc.artFor(a), true, "cover shown for its own track")
    svc.request(b); svc.artProbeDelay.stop()
    eq(svc.artFor(b), true, "previous cover lingers while the next one settles")
    eq(svc.artFor(a), true, "the measured URL still matches its cover")
    svc.finishAttempt(b, 1)
    eq(svc.artFor(b), false, "failed fetch drops the previous cover")
    eq(svc.artFile, "", "no cover kept after the failure")
    svc.request(a); svc.artProbeDelay.stop()
    svc.applyArtProbe(a, "MEAN 336699\nART /tmp/a.png\n")
    svc.applyArtProbe(b, "MEAN 000000\nART /tmp/b.png\n")
    eq(svc.artFile, "/tmp/a.png", "a late answer for another track is ignored")
    svc.request(b); svc.artProbeDelay.stop()
    svc.applyArtProbe(b, "garbage")
    eq(svc.artFor(b), false, "unreadable probe output shows no cover")
    svc.request("")
    svc.artProbeDelay.stop()

    // Equalizer and marquee gates.
    eq(equalizer.stepping, !FoamyMotion.reduceMotion, "equalizer steps while shown and playing")
    equalizer.animate = false
    eq(equalizer.stepping, false, "equalizer still while its popup or bar is hidden")
    equalizer.animate = true
    equalizer.playing = false
    eq(equalizer.stepping, false, "equalizer still while paused")
    eq(barContent.panning, false, "title does not pan while paused")
    barContent.playing = true
    eq(barContent.panning, !FoamyMotion.reduceMotion, "long title pans while playing")
    eq(barContent.progressShown, true, "underline shows with the popup closed")
    barContent.popupOpen = true
    eq(barContent.panning, false, "title rests while the popup is open")
    eq(barContent.progressShown, false, "underline hidden under the open-panel mark")

    // The cursor over a playing player. Transport and sliders keep their
    // physical direction in RTL, where PanelKeyCatcher reports reading order.
    var physical = playerView.LayoutMirroring.enabled ? -1 : 1
    playerView.moveRequested(0, 1)
    eq(playerView.cursorKey, "playPause", "first move lands on play/pause")
    playerView.moveRequested(-physical, 0)
    eq(playerView.cursorKey, "previous", "left moves to previous")
    playerView.activateRequested()
    playerView.moveRequested(0, -1)
    eq(playerView.cursorKey, "seek", "up reaches the timeline")
    // Sliders (DESIGN.md "Sliders"): the cursor rings the thumb, the row
    // behind it stays unfilled.
    var seekSlider = findNamed(playerView, "mediaSeekSlider")
    var volumeSlider = findNamed(playerView, "mediaVolumeSlider")
    check(seekSlider !== null && volumeSlider !== null, "seek and volume sliders exist")
    if (seekSlider && volumeSlider) {
      eq(seekSlider.hasCursor, true, "the cursor on the timeline rings its thumb")
      eq(volumeSlider.hasCursor, false, "only the slider with the cursor is ringed")
      var row = seekSlider.parent ? seekSlider.parent.parent : null
      eq(row && row.color !== undefined, false, "no filled row behind the timeline")
      eq(volumeSlider.parent && volumeSlider.parent.color !== undefined, false, "no filled row behind the volume")
    }
    playerView.moveRequested(physical, 0)
    playerView.moveRequested(0, 1)
    eq(playerView.cursorKey, "playPause", "down from the timeline lands on play/pause")
    playerView.moveRequested(0, 1)
    eq(playerView.cursorKey, "volume", "down reaches the volume")
    if (volumeSlider) eq(volumeSlider.hasCursor, true, "the cursor on the volume rings its thumb")
    playerView.moveRequested(physical, 0)
    playerView.moveRequested(0, 1)
    eq(playerView.cursorKey, "tab:spotify", "down reaches the source tabs")
    playerView.moveRequested(1, 0)
    eq(playerView.cursorKey, "tab:youtube", "along the tabs in reading order")
    playerView.activateRequested()
    playerView.tabRequested(1)
    eq(JSON.stringify(player.calls), JSON.stringify(["previous", "seekBy:5", "volume:55", "select:youtube", "switch:1"]),
      "cursor actions")
    // The hero band carries the cover as its picture (blurred on the GPU,
    // cover-fitted under the kit scrim on the software renderer).
    var gpu = playerView.effectsAvailable
    eq(gpu, false, "the harness renders in software")
    eq(playerView.band.title, "Spotify", "band title names the source")
    eq(playerView.band.imageSource.toString(), "", "no cover, no picture")
    player.artSource = "file:///tmp/foamy-media-cover.png"
    eq(playerView.band.imageSource.toString(), gpu ? "" : "file:///tmp/foamy-media-cover.png", "cover is the band picture")
    eq(playerView.band.background !== null, gpu, "blurred cover only on the GPU renderer")
    // Regression (kit 0.3.2): the band holds only the current cover.
    for (var n = 1; n <= 5; n++) player.artSource = "file:///tmp/foamy-media-cover-" + n + ".png"
    eq(playerView.band.loadedImage, gpu ? "" : "file:///tmp/foamy-media-cover-5.png", "only the current cover is held after cycling")
    player.artSource = ""
    eq(playerView.band.loadedImage, "", "cleared cover (popup closed) is unloaded")
    player.artSource = "file:///tmp/foamy-media-cover.png"
    player.artBackground = false
    eq(playerView.band.imageSource.toString(), "", "Artwork background off keeps the foamy wash")
    eq(playerView.band.loadedImage, "", "and holds no picture")
    player.artBackground = true
    player.artSource = ""
    // Short screen: the player scrolls and keeps the cursor row in view.
    var scroll = null
    for (var c = 0; c < playerView.children.length; c++)
      if (playerView.children[c].objectName === "mediaMainScroll") scroll = playerView.children[c]
    check(scroll !== null, "main view has a scroll area")
    if (scroll) {
      eq(scroll.interactive, false, "no scrolling while the player fits")
      playerView.height = 220
      eq(scroll.interactive, true, "the player scrolls when the popup is shorter than it")
      playerView.place("launch")
      check(scroll.contentY > 0 && scroll.contentY + scroll.height >= scroll.contentHeight - 1, "cursor on the footer scrolls it into view")
      playerView.place("settings")
      eq(scroll.contentY, 0, "cursor on the header scrolls back up")
      playerView.place("tab:youtube")
      playerView.height = playerView.implicitHeight
    }
    player.opened = false
    eq(playerView.cursorKey, "tab:youtube", "cursor kept until reopened")
    player.opened = true
    eq(playerView.cursorKey, "", "cursor reset on open")
    player.live = false
    player.volumeSupported = false
    eq(JSON.stringify(playerView.stops), JSON.stringify(["settings", "tab:spotify", "tab:youtube", "launch"]), "stops follow the player")

    first.open()
    stepTwo.start()
  }

  Timer {
    id: stepTwo
    interval: 600
    onTriggered: {
      var first = panels.itemAt(0)
      var view = first.popup.bodyItem
      check(view !== null, "body built on open")
      eq(first.member.demanded, true, "open popup raises demand")
      eq(first.imagesActive, true, "covers decode while open")
      if (!view) { shell.finish(); return }
      eq(view.cursorKey, "", "no cursor highlight on open")
      view.moveRequested(0, 1)
      eq(view.cursorKey, "settings", "first move lands on the first stop when nothing plays")
      view.moveRequested(0, 1)
      eq(view.cursorKey, "tab:spotify", "down reaches the source row")
      view.moveRequested(1, 0)
      eq(view.cursorKey, "launch", "along the source row")
      eq(view.LayoutMirroring.enabled, shell.lang === "ar", "popup body mirrors in RTL only")
      var titles = { en: "Not running", no: "Ikke startet", ar: "Not running" }
      if (shell.lang !== "ar") eq(FoamyI18n.t("Not running"), titles[shell.lang], "translated")
      eq(FoamyI18n.t("%1 is not running", "Spotify"), shell.lang === "no" ? "Spotify er ikke startet" : "Spotify is not running", "parameter")
      shell.key(view, "s")
      eq(first.editingSettings, true, "s opens Settings")
      eq(view.blocked, true, "settings page owns the keys")
      first.save("showArtist", false)
      eq(mockBar.saved.length, 1, "setting saved inline")
      if (mockBar.saved.length === 1) {
        eq(mockBar.saved[0].id, "foamy.media", "saved to the widget's own entry")
        eq(mockBar.saved[0].settings.showArtist, false, "saved value")
        eq(mockBar.saved[0].settings.extra, "kept", "unknown keys kept")
      }
      first.saveMany({ youtubeAppId: "chromium-youtube.com__-Default", youtubeBrowser: "chromium" })
      eq(mockBar.saved.length, 3, "browser suggestion saved key by key")
      if (mockBar.saved.length === 3) {
        eq(mockBar.saved[2].settings.youtubeAppId, "chromium-youtube.com__-Default", "earlier key kept by the later save")
        eq(mockBar.saved[2].settings.youtubeBrowser, "chromium", "later key")
      }
      first.saveMany({ youtubeBrowser: "--evil", youtubeProfile: "Default" })
      eq(mockBar.saved.length, 3, "an invalid suggestion writes nothing")
      check(first.settingsError !== "", "invalid value reported")
      eq(first.retryable, false, "an invalid value is not offered for retry")
      eq(first.preference("showArtist"), false, "saved value read back before the host reflects it")
      // Regression: a settings field follows a change made elsewhere (another
      // monitor, the bar editor) after being focused and left unchanged, and
      // leaving it again doesn't save the stale value back.
      var width = shell.findKey(view.settingsPage, "maxLabelWidth")
      check(width !== null, "label width field")
      if (width) {
        var before = mockBar.saved.length
        width.commitEdit(true)                       // tabbed through, unchanged
        first.settings = ({ id: "foamy.media", hideWhenClosed: false, extra: "kept", maxLabelWidth: 320 })
        eq(width.field.text, width.format(320), "field shows the external change")
        width.commitEdit(true)
        eq(mockBar.saved.length, before, "leaving it unchanged saves nothing")
        width.field.text = "abc"; width.dirty = true
        check(width.handleKey(Qt.Key_Escape), "Escape is taken by the field")
        eq(width.field.text, width.format(320), "Escape restores the value")
        eq(first.editingSettings, true, "and the page stays")
        width.field.text = "250"; width.dirty = true
        width.commitEdit(false)
        eq(mockBar.saved.length, before + 1, "a changed value commits once")
        eq(mockBar.saved[mockBar.saved.length - 1].settings.maxLabelWidth, 250, "saved value")
      }
      var browser = shell.findKey(view.settingsPage, "youtubeBrowser")
      check(browser !== null, "browser field")
      if (browser) {
        browser.field.text = "--evil"; browser.dirty = true
        browser.commitEdit(false)
        check(browser.error !== "", "an invalid browser name is refused in the field")
        browser.commitEdit(true)
        eq(browser.field.text, browser.value, "focus-out restores the saved name")
      }
      // Regression: on a host that reflects an inline save at once (4.5), the
      // saved value must not stay pending and mask a later outside change,
      // which the next save (merging the whole entry) would undo.
      first.settings = JSON.parse(JSON.stringify(first.effectiveSettings))  // the host caught up
      var base = JSON.parse(JSON.stringify(first.settings))
      base.showArtist = true
      first.settings = base
      eq(first.preference("showArtist"), true, "no saves pending")
      var plainShell = mockBar.shell
      mockBar.shell = reflectingShell
      reflectingShell.panel = first
      var savedBefore = mockBar.saved.length
      first.save("showArtist", false)
      eq(mockBar.saved.length, savedBefore + 1, "saved inline")
      eq(first.settings.showArtist, false, "the host reflected the save at once")
      var elsewhere = JSON.parse(JSON.stringify(first.settings))
      elsewhere.showArtist = true                   // another monitor turns it back on
      first.settings = elsewhere
      eq(first.preference("showArtist"), true, "an outside change after a reflected save shows")
      first.save("showProgress", !first.preference("showProgress"))
      eq(mockBar.saved[mockBar.saved.length - 1].settings.showArtist, true, "the next save keeps the outside change")
      mockBar.shell = plainShell
      first.closeSettings()
      eq(view.blocked, false, "back from Settings")
      first.close()
      stepThree.start()
    }
  }

  Timer {
    id: stepThree
    interval: 1300
    onTriggered: {
      var first = panels.itemAt(0)
      eq(first.member.demanded, false, "closing releases demand")
      eq(first.imagesActive, false, "covers released after closing")
      eq(first.editingSettings, false, "closing leaves Settings")
      // The settings IPC on a closed popup lands on Settings (reset on close only).
      first.openSettings()
      eq(first.opened, true, "settings opens the popup")
      eq(first.editingSettings, true, "and lands on Settings")
      first.close()
      eq(first.editingSettings, false, "closing resets it")
      // A widget hidden by "Hide when stopped" opened through IPC: centred
      // under the bar, not in the screen corner.
      var hidden = hiddenPanel.createObject(barRow, { bar: mockBar, moduleName: "foamy.media", settings: ({ id: "foamy.media" }) })
      eq(hidden.shown, false, "nothing playing hides the widget")
      eq(hidden.popup.centerOnBar, true, "hidden widget centres its popup")
      hidden.open()
      stepFour.hidden = hidden
      stepFour.start()
    }
  }

  Component {
    id: hiddenPanel
    Media.Panel {}
  }
  Timer {
    id: stepFour
    property var hidden: null
    interval: 600
    onTriggered: {
      var popup = hidden.popup
      check(popup.screenW > 0, "popup knows its screen")
      eq(popup.cardOrigin.x, Math.round(Math.max(popup.margin, Math.min(popup.screenW / 2 - popup.contentWidth / 2,
        popup.screenW - popup.contentWidth - popup.margin))), "card centred on the screen")
      check(popup.cardOrigin.x > popup.margin && popup.cardOrigin.y > 0, "not in the top-left corner")
      eq(panels.itemAt(0).popup.centerOnBar, false, "a shown widget still hangs from itself")
      hidden.close()
      hidden.destroy()
      shell.finish()
    }
  }

  property int holdMs: Number(Quickshell.env("FOAMY_HOLD_MS") || 0)
  function finish() {
    console.log("FOAMY RESULT " + host + "/" + lang + " " + checks + " checks, " + failures + " failures")
    console.log("FOAMY READY")
    finishTimer.start()
  }
  Timer {
    id: finishTimer
    interval: shell.holdMs
    onTriggered: { console.log("FOAMY DONE"); Qt.quit() }
  }
}
