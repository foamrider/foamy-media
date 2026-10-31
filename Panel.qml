pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "kit/FoamyPrefs.js" as Prefs
import "Model.js" as Model
import "Preferences.js" as Schema
import "BrowserSetup.js" as BrowserSetup

// The media bar widget (one per monitor on 4.5). State every bar shares (the
// selected source, the album-art probe) lives in the MediaService singleton;
// the leader (FoamyMember) runs the source reconciliation, the art request,
// the position tick and IPC. This file owns the bar entry, the player API the
// popup reads, and settings saving. MediaView draws the popup body from the
// API below (preview/Preview.qml feeds a mock of it).
Panel {
  id: root

  moduleName: "foamy.media"
  ipcTarget: "foamy.media"
  // The base only wires open/close/toggle; the transport calls live on the
  // same target, so FoamyIpc below owns the whole handler.
  manageIpc: false

  readonly property alias popup: popup
  readonly property alias member: member

  FoamyMember { id: member; scope: "media"; demanding: root.opened }

  // ---------------------------------------------------------------- settings
  // Saved values (and saves not yet reflected back) through the kit queue.
  FoamyPrefsQueue {
    id: prefs
    bar: root.bar
    moduleName: root.moduleName
    fields: Schema.schema
    settings: root.settings
  }
  function preference(key) { return prefs.value(key) }
  readonly property var effectiveSettings: prefs.effectiveSettings
  readonly property int maxLabelWidth: Style.space(preference("maxLabelWidth"))
  readonly property bool showArtist: preference("showArtist")
  readonly property bool showProgress: preference("showProgress")
  readonly property bool hideWhenStopped: preference("hideWhenClosed")
  readonly property string scrollAction: preference("scrollAction")
  readonly property string leftClick: preference("leftClick")
  readonly property string accentChoice: preference("accent")
  readonly property bool artBackground: preference("artBackground")
  readonly property int artIntensity: preference("artIntensity")
  readonly property bool animateTitle: preference("animateTitle")
  readonly property bool showEqualizer: preference("showEqualizer")
  readonly property bool youtubeEnabled: preference("youtubeEnabled")
  readonly property int volumeStep: preference("volumeStep")

  FoamySettingsState {
    id: settingsState
    panel: root
    onHidden: { root.browserSettingsOpen = false; root.localError = "" }
  }
  readonly property bool editingSettings: settingsState.editing
  property bool browserSettingsOpen: false
  // Errors that are not a save (a failed paste, the browser not starting).
  property string localError: ""
  readonly property bool saving: prefs.busy
  readonly property string settingsError: localError !== "" ? localError : prefs.error
  readonly property bool retryable: localError === "" && prefs.canRetry

  function openSettings() { settingsState.show() }
  function closeSettings() { settingsState.hide() }

  function save(key, value) {
    var values = {}
    values[key] = value
    saveMany(values)
  }
  // Several keys at once (the browser picker writes up to four): every value
  // is checked before any is written, then the queue saves them in order,
  // each merged over the ones before.
  function saveMany(values) {
    localError = ""
    var keys = Object.keys(values)
    for (var i = 0; i < keys.length; i++) {
      if (!Prefs.valid(Schema.schema, keys[i], values[keys[i]])) { localError = "That value isn't allowed."; return false }
    }
    for (var j = 0; j < keys.length; j++) prefs.save(keys[j], values[keys[j]])
    return true
  }
  function retrySave() { localError = ""; prefs.retry() }

  readonly property var browserCandidates: editingSettings && browserSettingsOpen
    ? BrowserSetup.candidates(ToplevelManager.toplevels.values || [], players, DesktopEntries.applications.values || []) : []

  // ------------------------------------------------------------------- theme
  // Source brand colours: the default accent is the source's own colour.
  readonly property color spotifyGreen: "#1DB954" // foamy-lint: allow hex-colour — Spotify brand colour, the widget's "Source color" accent
  readonly property color youtubeRed: "#FF0033" // foamy-lint: allow hex-colour — YouTube brand colour, the widget's "Source color" accent
  readonly property color sourceBrandColor: sourceKind === "youtube" ? youtubeRed : spotifyGreen
  readonly property color accentColor: accentChoice === "Album art" ? artAccent
    : accentChoice === "Theme accent" ? Commons.Color.accent
    : accentChoice === "Bar foreground" ? barForeground
    : sourceBrandColor
  // The cover's own colour, lifted until it reads as an accent. The source
  // colour stands in until the probe answers for this track.
  readonly property color artAccent: artDominant === "" ? sourceBrandColor : Model.ensureContrast(artDominant, 0.48)
  readonly property bool vertical: bar ? bar.vertical : false
  // Short screens (or a tall bar) get the smaller cover and title.
  readonly property bool compactPanel: popup.availableCardHeight > 0 && popup.availableCardHeight < Style.space(500)

  // ------------------------------------------------------------------ player
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property int toplevelGeneration: 0
  readonly property string selectedSource: MediaService.selectedSource

  readonly property var youtubeWindow: {
    if (!root.youtubeEnabled) return null
    var generation = root.toplevelGeneration
    var appId = root.preference("youtubeAppId")
    var values = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].appId || "") === appId) return values[i]
    }
    return null
  }
  readonly property var spotifyPlayer: Model.findSpotify(players, MprisPlaybackState.Stopped)
  readonly property bool spotifyOpen: spotifyPlayer !== null && spotifyPlayer !== undefined
  readonly property bool youtubeOpen: youtubeWindow !== null && youtubeWindow !== undefined
  readonly property bool anySourceOpen: spotifyOpen || youtubeOpen
  readonly property var youtubeCandidate: Model.findYoutube(
    players,
    youtubeWindow ? String(youtubeWindow.title || "") : "",
    MprisPlaybackState.Stopped, root.preference("youtubeMprisName"))
  // The MPRIS service is shared by the whole browser profile. Requiring the
  // exact web-app toplevel and Model's URL or exact title correlation keeps
  // an ordinary browser media tab from being treated as this YouTube app.
  readonly property var youtubePlayer: youtubeWindow ? youtubeCandidate : null
  readonly property bool youtubeHasTrack: Model.hasDisplayableTrack(youtubePlayer, MprisPlaybackState.Stopped)
  readonly property bool spotifyHasTrack: Model.hasDisplayableTrack(spotifyPlayer, MprisPlaybackState.Stopped)
  readonly property bool spotifyPlaying: spotifyOpen && spotifyPlayer.isPlaying === true
  readonly property bool youtubePlaying: youtubeHasTrack && youtubePlayer.isPlaying === true
  readonly property bool bothPlaying: spotifyPlaying && youtubePlaying
  readonly property string sourceKind: selectedSource
  readonly property string sourceName: sourceKind === "youtube" ? "YouTube" : "Spotify"
  readonly property string sourceIcon: sourceKind === "youtube" ? "\u{f16a}" : "\u{f1bc}"
  readonly property bool sourceOpen: sourceKind === "youtube" ? youtubeOpen : spotifyOpen
  readonly property var player: sourceKind === "youtube" ? youtubePlayer : spotifyPlayer
  readonly property bool live: player !== null && player !== undefined
  readonly property bool playing: live && player.isPlaying === true

  readonly property string trackTitle: live ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: live ? String(player.trackArtist || "") : ""
  readonly property string trackAlbum: live ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: live ? String(player.trackArtUrl || "") : ""
  readonly property string label: Model.barLabel(player, showArtist)

  readonly property real trackLength: live && player.lengthSupported ? Math.max(0, player.length) : 0
  // Quickshell extrapolates position between polls, so it can overshoot the
  // track length by a fraction of a second right before a track change.
  readonly property real trackPosition: {
    if (!live || !player.positionSupported) return 0
    var pos = Math.max(0, player.position)
    return trackLength > 0 ? Math.min(pos, trackLength) : pos
  }
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0

  readonly property bool canSeek: live && player.canSeek && trackLength > 0
  readonly property bool canGoPrevious: live && player.canGoPrevious === true
  readonly property bool canGoNext: live && player.canGoNext === true
  // Shuffle and repeat are Spotify-only: the browser reports them but ignores writes.
  readonly property bool shuffleSupported: sourceKind === "spotify" && live && player.shuffleSupported === true
  readonly property bool loopSupported: sourceKind === "spotify" && live && player.loopSupported === true
  readonly property bool volumeSupported: live && player.volumeSupported === true
  readonly property real volume: volumeSupported ? player.volume : 0
  readonly property bool shuffleOn: live && player.shuffleSupported && player.shuffle === true
  readonly property int loopState: live && player.loopSupported ? player.loopState : MprisLoopState.None
  readonly property string loopName: loopState === MprisLoopState.Track ? "track"
    : loopState === MprisLoopState.Playlist ? "playlist" : "off"

  readonly property bool shown: Model.shouldShowWidget(spotifyPlayer, youtubePlayer, hideWhenStopped, MprisPlaybackState.Stopped)

  // Source selection is shared; the leader keeps it in step with the players.
  function chooseInitialSource() {
    var next = Model.initialSource(root.bothPlaying, !!(root.youtubeWindow && root.youtubeWindow.activated),
      root.youtubePlaying, root.spotifyHasTrack, root.youtubeHasTrack, root.spotifyOpen, root.youtubeOpen)
    if (next) MediaService.selectedSource = next
  }
  function reconcileSource() {
    if (!member.isLeader) return
    MediaService.selectedSource = Model.reconcileSource(MediaService.selectedSource, {
      spotifyPlaying: root.spotifyPlaying, youtubePlaying: root.youtubePlaying,
      spotifyHasTrack: root.spotifyHasTrack, youtubeHasTrack: root.youtubeHasTrack,
      spotifyOpen: root.spotifyOpen, youtubeOpen: root.youtubeOpen
    })
  }
  function selectSource(kind) {
    if ((kind === "spotify" && root.spotifyOpen) || (kind === "youtube" && root.youtubeOpen))
      MediaService.selectedSource = kind
  }
  // MPRIS and toplevel changes can arrive while QML is evaluating `player`.
  // Apply the selection after that update so the newest transition still
  // wins without mutating one of the binding's inputs mid-evaluation.
  function deferPlaybackTransition(kind, becamePlaying) {
    if (!member.isLeader) return
    Qt.callLater(function() {
      var stillPlaying = kind === "youtube" ? root.youtubePlaying : root.spotifyPlaying
      if (becamePlaying && stillPlaying) MediaService.selectedSource = kind
      else if (!becamePlaying && MediaService.selectedSource === kind) root.reconcileSource()
    })
  }
  function deferReconcile() { if (member.isLeader) Qt.callLater(root.reconcileSource) }
  onSpotifyPlayingChanged: deferPlaybackTransition("spotify", spotifyPlaying)
  onYoutubePlayingChanged: deferPlaybackTransition("youtube", youtubePlaying)
  onSpotifyPlayerChanged: deferReconcile()
  onYoutubePlayerChanged: deferReconcile()
  onYoutubeHasTrackChanged: deferReconcile()
  onSpotifyOpenChanged: deferReconcile()
  onYoutubeOpenChanged: deferReconcile()

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.toplevelGeneration++ }
  }

  // ------------------------------------------------------------- album art
  // The leader asks the shared service for the current cover; every bar
  // reads the answer. artShown is false as soon as the cover on file is not
  // this track's (a failed or pending fetch), so a previous track's cover,
  // colour and scrim never sit next to a new title.
  readonly property bool artShown: MediaService.artFor(artUrl)
  readonly property string artDominant: artShown ? MediaService.artDominant : ""
  readonly property real artLuma: artShown ? MediaService.artLuma : 0
  // Covers are decoded only while the popup is open (and briefly after, so
  // reopening does not flash); the bar never shows one.
  property bool imagesActive: false
  readonly property string artSource: artShown && imagesActive ? Model.fileUrl(MediaService.artFile) : ""

  function requestArt() { if (member.isLeader) MediaService.request(root.artUrl) }
  onArtUrlChanged: requestArt()
  Connections {
    target: member
    function onIsLeaderChanged() {
      root.requestArt()
      root.reconcileSource()
    }
  }
  Component.onCompleted: Qt.callLater(function() {
    if (!member.isLeader) return
    root.chooseInitialSource()
    root.requestArt()
  })

  onOpenedChanged: {
    if (opened) {
      imageRelease.stop()
      imagesActive = true
    } else {
      imageRelease.restart()
    }
  }
  Timer {
    id: imageRelease
    interval: 1000
    onTriggered: if (!root.opened) root.imagesActive = false
  }

  // ----------------------------------------------------------------- actions
  function playPause() {
    if (!live) {
      launch()
      return false
    }
    if (player.canTogglePlaying) {
      player.togglePlaying()
      return true
    }
    if (playing && player.canPause) {
      player.pause()
      return true
    }
    if (!playing && player.canPlay) {
      player.play()
      return true
    }
    return false
  }
  function skipNext() {
    if (!canGoNext) return false
    player.next()
    return true
  }
  function skipPrevious() {
    if (!canGoPrevious) return false
    player.previous()
    return true
  }
  function seekTo(seconds) {
    if (!canSeek) return false
    player.position = Math.max(0, Math.min(trackLength, seconds))
    return true
  }
  function seekBy(seconds) { return seekTo(trackPosition + seconds) }
  function setVolume(value) {
    if (!volumeSupported) return false
    player.volume = Math.max(0, Math.min(1, value))
    return true
  }
  function nudgeVolume(delta) { return volumeSupported && setVolume(player.volume + delta) }
  function toggleShuffle() {
    if (!shuffleSupported) return false
    player.shuffle = !player.shuffle
    return true
  }
  function cycleLoop() {
    if (!loopSupported) return false
    player.loopState = loopState === MprisLoopState.None ? MprisLoopState.Playlist
      : loopState === MprisLoopState.Playlist ? MprisLoopState.Track
      : MprisLoopState.None
    return true
  }

  // YouTube already has an exact reactive toplevel identity, so activate that
  // directly. Spotify keeps Omarchy's installer-aware launch path.
  function launch() {
    if (root.sourceKind === "youtube") {
      if (root.youtubeWindow) {
        root.youtubeWindow.activate()
      } else {
        youtubeLaunch.command = Schema.youtubeLaunch(root.preference("youtubeBrowser"), root.preference("youtubeProfile"))
        youtubeLaunch.running = true
      }
      return
    }
    if (bar) bar.run("omarchy launch spotify")
  }
  Process {
    id: youtubeLaunch
    stderr: StdioCollector { id: launchError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      console.warn("foamy-media: starting the browser failed:", launchError.text.trim())
      root.localError = "Couldn't start the browser."
      root.openSettings()
      root.browserSettingsOpen = true
    }
  }

  function statusObject() {
    return {
      running: root.sourceOpen,
      controllable: root.live,
      playing: root.playing,
      playbackState: root.live ? MprisPlaybackState.toString(root.player.playbackState) : "Stopped",
      source: root.sourceKind,
      spotifyPlaying: root.spotifyPlaying,
      youtubePlaying: root.youtubePlaying,
      title: root.trackTitle,
      artist: root.trackArtist,
      album: root.trackAlbum,
      artUrl: root.artUrl,
      artShown: root.artShown,
      position: root.trackPosition,
      length: root.trackLength,
      shuffle: root.shuffleOn,
      loop: root.loopName,
      leftClick: root.leftClick,
      language: FoamyI18n.language,
      open: root.opened,
      editingSettings: root.editingSettings,
      leader: member.isLeader,
      revision: 11
    }
  }

  // ---- IPC (one handler per shell) ---------------------------------------
  FoamyIpc {
    target: "foamy.media"
    enabled: member.isLeader
    function settings(): void { root.openSettings() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function next(): string { return root.skipNext() ? "ok" : "unhandled" }
    function previous(): string { return root.skipPrevious() ? "ok" : "unhandled" }
    function shuffle(): string { return root.toggleShuffle() ? "ok" : "unhandled" }
    function loop(): string { return root.cycleLoop() ? "ok" : "unhandled" }
    function launch(): void { root.launch() }
    function status(): string { return JSON.stringify(root.statusObject()) }
  }

  // MPRIS position is only re-read when something asks for it. One tick per
  // shell (every bar reads the same player): as often as the underline gains
  // a pixel while it shows, every half second while a popup shows the time.
  Timer {
    running: member.isLeader && root.playing && (member.demanded || (root.showProgress && !root.vertical))
    interval: member.demanded ? 500 : Model.progressTickInterval(root.trackLength, barContent.progressWidth)
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ---------------------------------------------------------------- bar entry
  visible: shown
  implicitWidth: shown ? barContent.implicitWidth : 0
  implicitHeight: shown ? barContent.implicitHeight : 0

  BarContent {
    id: barContent
    anchors.fill: parent
    vertical: root.vertical
    barSize: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    glyph: root.sourceIcon
    glyphColor: !root.live ? Qt.darker(root.barForeground, 1.9)
      : root.playing ? root.accentColor : Qt.darker(root.accentColor, 1.5)
    colorAnimation: !root.bar || root.bar.foregroundAnimationEnabled
    label: root.label
    labelColor: root.barForeground
    maxLabelWidth: root.maxLabelWidth
    animateTitle: root.animateTitle
    live: root.live
    playing: root.playing
    showEqualizer: root.showEqualizer
    accent: root.accentColor
    showProgress: root.showProgress && root.trackLength > 0
    progress: root.progress
    popupOpen: root.opened
  }

  // The bar overlays every widget slot with its own pointer handler for
  // drag-to-reorder. It forwards a click only to a slot that exposes
  // triggerPress(), and that same check drives the pointer cursor and the
  // open-panel indicator, so the click policy lives here rather than in a
  // MouseArea of our own. Buttons the bar does not forward still reach the
  // MouseArea below, which routes them back to this function.
  function triggerPress(button) {
    if (bar) bar.hideTooltip(root)
    var name = button === Qt.LeftButton ? "left" : button === Qt.RightButton ? "right"
      : button === Qt.MiddleButton ? "middle" : ""
    var action = Schema.clickAction(name, root.leftClick)
    if (action === "next") { if (live) skipNext(); return }
    if (action === "panel") toggle()
    else if (action === "playPause") playPause()
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.RightButton | Qt.MiddleButton

    // Qt::ScrollPhase, compared numerically so this does not depend on the Qt
    // namespace enum being exposed to QML.
    readonly property int phaseNone: 0
    readonly property int phaseBegin: 1
    readonly property int phaseEnd: 3
    readonly property int phaseMomentum: 4

    // A mouse reports one 120-unit notch per detent. A touchpad reports a
    // stream of small deltas for a single two-finger swipe, so the notch model
    // would skip several tracks per gesture. Track skipping is therefore
    // gesture-based: one skip per swipe, no matter how far the fingers travel.
    property real wheelAccumulator: 0
    property bool gestureSkipped: false
    // How far a swipe must travel before it counts, so resting fingers or a
    // stray brush while reaching for the bar do not change the track.
    readonly property real gestureThreshold: 50
    readonly property real notch: 120

    function endGesture() {
      pointer.wheelAccumulator = 0
      pointer.gestureSkipped = false
    }

    onClicked: function(mouse) { root.triggerPress(mouse.button) }

    onWheel: function(wheel) {
      if (!root.live || root.scrollAction === "Nothing") return
      // Kinetic scrolling after the fingers lift is not a deliberate request.
      if (wheel.phase === pointer.phaseMomentum) return
      if (wheel.phase === pointer.phaseBegin) pointer.endGesture()
      if (wheel.phase === pointer.phaseEnd) {
        pointer.endGesture()
        return
      }

      // A touchpad sets a scroll phase or reports pixel deltas; a mouse wheel
      // arrives as bare 120-unit steps. Some drivers report neither phase nor
      // pixels, so a sub-notch delta is treated as continuous scrolling too.
      var continuous = wheel.phase !== pointer.phaseNone
        || wheel.pixelDelta.y !== 0
        || Math.abs(wheel.angleDelta.y) < pointer.notch

      pointer.wheelAccumulator += wheel.angleDelta.y
      // The gesture is over once the events stop, which is the only end signal
      // available when the driver reports no phase.
      gestureIdle.restart()

      if (root.scrollAction === "Volume") {
        // Volume is continuous, so every step counts on both kinds of device,
        // scaled so a swipe is not a jump to the extremes.
        var volumeStep = continuous ? pointer.notch * 2 : pointer.notch
        while (Math.abs(pointer.wheelAccumulator) >= volumeStep) {
          var volumeUp = pointer.wheelAccumulator > 0
          pointer.wheelAccumulator += volumeUp ? -volumeStep : volumeStep
          root.nudgeVolume((volumeUp ? 1 : -1) * root.volumeStep / 100)
        }
        return
      }

      if (continuous) {
        if (pointer.gestureSkipped || Math.abs(pointer.wheelAccumulator) < pointer.gestureThreshold) return
        pointer.gestureSkipped = true
        if (pointer.wheelAccumulator > 0) root.skipPrevious()
        else root.skipNext()
        return
      }

      // Discrete wheel: one skip per notch, rate limited so a fast spin does
      // not tear through the queue.
      if (Math.abs(pointer.wheelAccumulator) < pointer.notch) return
      var up = pointer.wheelAccumulator > 0
      pointer.wheelAccumulator = 0
      if (skipCooldown.running) return
      skipCooldown.restart()
      if (up) root.skipPrevious()
      else root.skipNext()
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.live
      ? (root.playing ? "" : FoamyI18n.t("Paused") + " — ") + Model.barLabel(root.player, true)
      : FoamyI18n.t("%1 is not running", root.sourceName))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Timer {
    id: gestureIdle
    interval: 220
    onTriggered: pointer.endGesture()
  }
  Timer {
    id: skipCooldown
    interval: 350
  }

  // ------------------------------------------------------------------ popup
  // A card-width anchor that starts at the widget's leading edge lines the
  // popup up with the widget. Vertical bars keep the stock centring.
  Item {
    id: popupLeftAnchor
    width: popup.contentWidth
    height: root.height
  }

  FoamyPopup {
    id: popup
    anchorItem: root.vertical ? root : popupLeftAnchor
    // A hidden widget (Hide when stopped) has no place on the bar to hang
    // from, so a popup opened through IPC is centred under the bar instead
    // of landing in the screen corner.
    centerOnBar: !root.shown
    bar: root.bar
    owner: root
    open: root.opened
    body: Component {
      MediaView { media: root }
    }
  }
}
