pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "Model.js" as Model

// State shared by every media bar instance (4.5 draws one bar per monitor).
// The selected source and the album-art probe live here, so two monitors show
// the same source and a track change downloads and decodes its cover once,
// not once per bar.
//
// Album colour. The panel wears the cover as its background, and "adaptive"
// is the whole point: a scrim strong enough for a near-white sleeve would bury
// a dark one, so the cover is measured and the scrim answers. Two numbers come
// back: the mean luminance, which sets how hard the scrim has to work, and the
// dominant colour, which tints it so the panel reads as part of the artwork.
// Qt can show the image but cannot tell us its colour, so an ImageMagick probe
// does the reading. Everything downstream falls back to the plain theme panel
// while that is unanswered or has failed, which is also what happens on a
// machine without ImageMagick.
QtObject {
  id: root

  // ------------------------------------------------------------------ source
  property string selectedSource: "spotify"

  // --------------------------------------------------------------- album art
  // The cover every bar currently shows (bars share selectedSource, so they
  // ask for the same one). request() is idempotent, so each bar may call it.
  property string artUrl: ""
  property string artDominant: ""
  property real artLuma: 0
  // The URL the values above describe: not necessarily the current one,
  // which is what stops a stale answer from repainting a new track.
  property string artProbed: ""
  // The normalised copy the probe wrote. The panel displays only this, never
  // `artUrl`: a QML Image handed a raw art URL would repeat none of the
  // probe's checks, and Qt would fetch any origin, follow redirects and decode
  // whatever its image plugins handle (SVG and PDF included) in the shell.
  property string artFile: ""
  // True for a moment after a track change while the new cover is first
  // fetched, so the old one can cross-fade instead of flashing the plain
  // panel. It ends when that first attempt finishes (or after a short cap):
  // a cover that fails to load is never shown next to another track.
  property bool artSettling: false
  property int artRetries: 0

  // Whether the stored cover belongs to `url` (or is the previous one,
  // allowed to linger while `url` settles).
  function artFor(url) {
    return artFile !== "" && url !== "" && (artProbed === url || (artSettling && url === artUrl))
  }

  function request(url) {
    var next = String(url || "")
    if (next === artUrl) return
    artUrl = next
    artRetry.stop()
    artRetries = 0
    artSettling = artFile !== "" && next !== ""
    if (artSettling) settleCap.restart()
    artProbeDelay.restart()
  }

  readonly property bool networkConnected: Networking.connectivity === NetworkConnectivity.Full
    || Networking.connectivity === NetworkConnectivity.Limited
  property bool networkSettled: false
  readonly property bool networkReady: networkConnected && networkSettled
  readonly property bool remoteArt: /^https?:\/\//i.test(artUrl)
  onNetworkConnectedChanged: networkSettled = false
  onNetworkReadyChanged: {
    artRetry.stop()
    artRetries = 0
    if (networkReady && remoteArt) artProbeDelay.restart()
  }

  function probeArt(force) {
    var target = Model.artProbeTarget(root.artUrl)
    if (!target) {
      root.forgetArt()
      return
    }
    if (!force && root.artProbed === root.artUrl) return
    if (remoteArt && !networkReady) {
      if (root.artProbed !== root.artUrl) root.forgetArt()
      return
    }
    artRetry.stop()

    // Wait for the cancelled process to exit before assigning a new request URL.
    if (artProbe.running) {
      if (artProbe.pending === root.artUrl) return
      artProbe.running = false
      artProbeDelay.restart()
      return
    }
    artProbe.pending = root.artUrl
    artProbe.command = ["/bin/sh", "-c", Model.artProbeScript(), "sh", target]
    artProbe.running = true
  }

  function forgetArt() {
    root.artFile = ""
    root.artDominant = ""
    root.artLuma = 0
    root.artProbed = ""
    root.artSettling = false
  }

  function applyArtProbe(url, text) {
    // A probe that finished after the track already moved on describes the
    // wrong cover, so drop it and let the newer one land.
    if (url !== root.artUrl) return

    var probe = Model.parseArtProbe(text)
    // Unreadable output means this track has no usable cover: never keep the
    // previous track's one in its place.
    if (!probe || !probe.file) {
      root.forgetArt()
      return
    }

    root.artRetries = 0
    artRetry.stop()
    root.artFile = probe.file
    root.artDominant = probe.dominant
    root.artLuma = probe.luma
    root.artProbed = url
    root.artSettling = false
  }

  // A failed attempt (fetch, size, format or decode) means the current track
  // has no cover right now: drop the previous one while any retry runs.
  function finishAttempt(url, exitCode) {
    if (url === root.artUrl && exitCode !== 0 && root.artProbed !== url) root.forgetArt()
  }

  property Timer networkSettle: Timer {
    // Local artwork remains available while DNS and routes settle.
    interval: 2000
    running: root.networkConnected && !root.networkSettled
    onTriggered: root.networkSettled = true
  }

  // Track changes arrive in bursts while skipping; only the settled one is
  // worth a subprocess and a download.
  property Timer artProbeDelay: Timer {
    interval: 250
    onTriggered: root.probeArt(false)
  }

  property Timer artRetry: Timer {
    onTriggered: root.probeArt(false)
  }

  property Timer settleCap: Timer {
    interval: 1500
    onTriggered: root.artSettling = false
  }

  property Process artProbe: Process {
    property string pending: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyArtProbe(root.artProbe.pending, text)
    }

    onExited: function(exitCode) {
      var url = pending
      // Let the stdout collector apply a successful result before deciding.
      Qt.callLater(function() {
        root.finishAttempt(url, exitCode)
        if (url !== root.artUrl || root.artProbed === root.artUrl
            || !root.remoteArt || !root.networkReady || root.artRetries >= 3) return
        root.artRetry.interval = 2500 * Math.pow(2, root.artRetries++)
        root.artRetry.restart()
      })
    }
  }
}
