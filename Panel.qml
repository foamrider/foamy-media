import QtQuick
import QtQuick.Effects
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Preferences.js" as Preferences

Panel {
  id: root

  moduleName: "foamy.media"
  ipcTarget: "foamy.media"
  // The base only wires open/close/toggle; this widget adds transport calls
  // on the same target, so it owns the whole handler.
  manageIpc: false

  // ---------------------------------------------------------------- settings
  function preference(key) { return Preferences.value(root.settings, key) }
  readonly property string language: Preferences.language(preference("language"), Qt.locale().name)
  function tr(value) { return Preferences.text(value, language) }
  readonly property int maxLabelWidth: Style.space(preference("maxLabelWidth"))
  readonly property bool showArtist: preference("showArtist")
  readonly property bool showProgress: preference("showProgress")
  readonly property bool showOpenPanelIndicator: !progressLine.visible
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
  property bool editingSettings: false
  property string settingsError: ""
  property var pendingPreferences: ({})

  function openSettings() {
    root.editingSettings = true
    root.open()
    mediaScroll.contentY = 0
    Qt.callLater(function() { settingsPane.focusBack() })
  }
  function closeSettings() {
    root.editingSettings = false
    mediaScroll.contentY = 0
    Qt.callLater(function() { settingsButton.forceActiveFocus() })
  }
  function savePreference(key, value) {
    if (!Preferences.valid(key, value)) {
      var field = Preferences.field(key)
      settingsError = tr("Invalid setting.") + (field ? " " + tr(field.label) : "")
      return
    }
    settingsError = ""
    // Coalesce rapid edits to a key while Omarchy persists the previous one.
    pendingPreferences[key] = value
    flushPreferences()
  }
  function flushPreferences() {
    if (preferencesSave.running) return
    var keys = Object.keys(pendingPreferences)
    if (!keys.length) return
    var key = keys[0]
    var value = pendingPreferences[key]
    delete pendingPreferences[key]
    preferencesSave.command = ["omarchy-shell", "shell", "setBarWidget", root.moduleName,
      key, " " + JSON.stringify(value), "{}"]
    preferencesSave.running = true
  }
  Process {
    id: preferencesSave
    stdout: StdioCollector { id: preferencesOutput; waitForEnd: true }
    stderr: StdioCollector { id: preferencesError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 || preferencesOutput.text.trim() !== "ok")
        root.settingsError = root.tr("Could not save settings.") + " "
          + String(preferencesError.text || preferencesOutput.text).trim()
      Qt.callLater(root.flushPreferences)
    }
  }
  onOpenedChanged: {
    if (!opened) { editingSettings = false; mediaScroll.contentY = 0 }
    else Qt.callLater(function() { if (!root.editingSettings) settingsButton.forceActiveFocus() })
  }

  // ------------------------------------------------------------------- theme
  readonly property color spotifyGreen: "#1DB954"
  readonly property color youtubeRed: "#FF0033"
  readonly property color sourceBrandColor: sourceKind === "youtube" ? youtubeRed : spotifyGreen
  readonly property color accentColor: accentChoice === "Album art" ? artAccent
    : accentChoice === "Theme accent" ? Color.accent
    : accentChoice === "Bar foreground" ? barForeground
    : sourceBrandColor
  // Optional hint for bars that support source-coloured widget borders.
  readonly property color islandBorderColor: sourceBrandColor
  // The cover's own colour, lifted until it is bright enough to read as an
  // accent. Falls back to the source colour until the probe answers, so nothing ever
  // flashes an unstyled colour on the first track of a session.
  readonly property color artAccent: artDominant === "" ? sourceBrandColor : Model.ensureContrast(artDominant, 0.48)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string panelFontFamily: "sans-serif"
  readonly property color panelMuted: Qt.tint(Color.popups.background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.76))
  readonly property color panelOutline: Qt.tint(Color.popups.background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22))
  readonly property color panelFill: Qt.tint(Color.popups.background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055))
  readonly property bool compactPanel: popup.availableCardHeight > 0 && popup.availableCardHeight < Style.space(500)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // ------------------------------------------------------------------ player
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property int toplevelGeneration: 0
  property string selectedSource: "spotify"

  readonly property var youtubeWindow: {
    if (!root.youtubeEnabled) return null
    var generation = root.toplevelGeneration
    var values = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].appId || "") === root.preference("youtubeAppId")) return values[i]
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
  // exact web-app toplevel and Model's URL or exact title correlation prevent
  // an ordinary browser media tab from being treated as this YouTube app.
  readonly property var youtubePlayer: youtubeWindow ? youtubeCandidate : null
  readonly property bool youtubeHasTrack: Model.hasDisplayableTrack(youtubePlayer, MprisPlaybackState.Stopped)
  readonly property bool spotifyHasTrack: Model.hasDisplayableTrack(spotifyPlayer, MprisPlaybackState.Stopped)
  readonly property bool spotifyPlaying: spotifyOpen && spotifyPlayer.isPlaying === true
  readonly property bool youtubePlaying: youtubeHasTrack && youtubePlayer.isPlaying === true
  readonly property bool bothPlaying: spotifyPlaying && youtubePlaying
  // Player-change handlers reconcile this imperative selection whenever a
  // source appears or disappears. Keeping this as a simple alias avoids a
  // binding loop while those handlers update selectedSource.
  readonly property string sourceKind: selectedSource
  readonly property string sourceName: sourceKind === "youtube" ? "YouTube" : "Spotify"
  readonly property string sourceIcon: sourceKind === "youtube" ? "" : ""
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
  // Quickshell keeps extrapolating position between polls, so it can overshoot
  // the track length by a fraction of a second right before a track change.
  readonly property real trackPosition: {
    if (!live || !player.positionSupported) return 0
    var pos = Math.max(0, player.position)
    return trackLength > 0 ? Math.min(pos, trackLength) : pos
  }
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0

  readonly property bool canSeek: live && player.canSeek && trackLength > 0
  readonly property bool shuffleOn: live && player.shuffleSupported && player.shuffle === true
  readonly property int loopState: live && player.loopSupported ? player.loopState : MprisLoopState.None
  readonly property string loopIcon: loopState === MprisLoopState.Track ? "󰑘"
    : loopState === MprisLoopState.Playlist ? "󰑖"
    : "󰑗"
  readonly property string loopName: loopState === MprisLoopState.Track ? "track"
    : loopState === MprisLoopState.Playlist ? "playlist"
    : "off"

  readonly property bool shown: Model.shouldShowWidget(
    spotifyPlayer,
    youtubePlayer,
    hideWhenStopped,
    MprisPlaybackState.Stopped)

  function chooseInitialSource() {
    if (root.bothPlaying) {
      root.selectedSource = root.youtubeWindow && root.youtubeWindow.activated ? "youtube" : "spotify"
    } else if (root.youtubePlaying) {
      root.selectedSource = "youtube"
    } else if (root.spotifyHasTrack) {
      root.selectedSource = "spotify"
    } else if (root.youtubeHasTrack) {
      root.selectedSource = "youtube"
    } else if (root.spotifyOpen) {
      root.selectedSource = "spotify"
    } else if (root.youtubeOpen) {
      root.selectedSource = "youtube"
    }
  }

  function reconcileSource() {
    if (root.youtubePlaying && !root.spotifyPlaying) {
      root.selectedSource = "youtube"
      return
    }
    if (root.spotifyPlaying && !root.youtubePlaying) {
      root.selectedSource = "spotify"
      return
    }

    // Keep a paused track selected over an open-but-empty app, regardless of
    // source, so the bar never falls back to a lonely launcher icon.
    var currentHasTrack = root.selectedSource === "youtube" ? root.youtubeHasTrack : root.spotifyHasTrack
    if (!currentHasTrack && root.spotifyHasTrack) {
      root.selectedSource = "spotify"
      return
    }
    if (!currentHasTrack && root.youtubeHasTrack) {
      root.selectedSource = "youtube"
      return
    }

    var currentOpen = root.selectedSource === "youtube" ? root.youtubeOpen : root.spotifyOpen
    if (currentOpen) return
    root.selectedSource = root.spotifyOpen ? "spotify" : root.youtubeOpen ? "youtube" : "spotify"
  }

  function selectSource(kind) {
    if (kind === "spotify" && root.spotifyOpen) root.selectedSource = "spotify"
    else if (kind === "youtube" && root.youtubeOpen) root.selectedSource = "youtube"
  }

  // MPRIS and toplevel changes can arrive while QML is evaluating `player`.
  // Apply the selection after that update finishes so the newest transition
  // still wins without mutating one of the binding's inputs mid-evaluation.
  function deferPlaybackTransition(kind, becamePlaying) {
    Qt.callLater(function() {
      var stillPlaying = kind === "youtube" ? root.youtubePlaying : root.spotifyPlaying
      if (becamePlaying && stillPlaying) {
        root.selectedSource = kind
      } else if (!becamePlaying && root.selectedSource === kind) {
        root.reconcileSource()
      }
    })
  }

  onSpotifyPlayingChanged: {
    deferPlaybackTransition("spotify", spotifyPlaying)
  }
  onYoutubePlayingChanged: {
    deferPlaybackTransition("youtube", youtubePlaying)
  }
  onSpotifyPlayerChanged: Qt.callLater(function() { root.reconcileSource() })
  onYoutubePlayerChanged: Qt.callLater(function() { root.reconcileSource() })
  onYoutubeHasTrackChanged: Qt.callLater(function() { root.reconcileSource() })
  onSpotifyOpenChanged: Qt.callLater(function() { root.reconcileSource() })
  onYoutubeOpenChanged: Qt.callLater(function() { root.reconcileSource() })

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.toplevelGeneration++ }
  }

  component PlaybackEqualizer: Item {
    id: equalizer

    required property color accent
    required property bool playing
    property bool showIdle: false
    readonly property int idleHeight: Style.space(3)

    implicitWidth: Style.space(10)
    implicitHeight: Style.space(9)
    width: implicitWidth
    height: implicitHeight
    opacity: playing || showIdle ? 1 : 0

    // An animation may stop between keyframes. Settle every stem at the
    // baseline after playback stops so the bar reads as idle, not frozen.
    function settleIdleBars() {
      equalizerOne.height = equalizer.idleHeight
      equalizerTwo.height = equalizer.idleHeight
      equalizerThree.height = equalizer.idleHeight
    }

    onPlayingChanged: if (!playing) Qt.callLater(equalizer.settleIdleBars)
    Component.onCompleted: if (!playing) settleIdleBars()

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: Style.space(8)
      height: parent.height
      spacing: Style.space(1)

      Item {
        width: Style.space(2)
        height: parent.height

        Rectangle {
          id: equalizerOne
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(3)
          radius: width / 2
          color: equalizer.accent
        }
      }

      Item {
        width: Style.space(2)
        height: parent.height

        Rectangle {
          id: equalizerTwo
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(7)
          radius: width / 2
          color: equalizer.accent
        }
      }

      Item {
        width: Style.space(2)
        height: parent.height

        Rectangle {
          id: equalizerThree
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(5)
          radius: width / 2
          color: equalizer.accent
        }
      }
    }

    SequentialAnimation {
      running: equalizer.playing && equalizer.visible
      loops: Animation.Infinite

      NumberAnimation {
        target: equalizerOne
        property: "height"
        from: Style.space(3)
        to: Style.space(8)
        duration: 240
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: equalizerOne
        property: "height"
        from: Style.space(8)
        to: Style.space(2)
        duration: 300
        easing.type: Easing.InOutSine
      }
    }

    SequentialAnimation {
      running: equalizer.playing && equalizer.visible
      loops: Animation.Infinite

      NumberAnimation {
        target: equalizerTwo
        property: "height"
        from: Style.space(7)
        to: Style.space(2)
        duration: 280
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: equalizerTwo
        property: "height"
        from: Style.space(2)
        to: Style.space(8)
        duration: 220
        easing.type: Easing.InOutSine
      }
    }

    SequentialAnimation {
      running: equalizer.playing && equalizer.visible
      loops: Animation.Infinite

      NumberAnimation {
        target: equalizerThree
        property: "height"
        from: Style.space(5)
        to: Style.space(8)
        duration: 200
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: equalizerThree
        property: "height"
        from: Style.space(8)
        to: Style.space(3)
        duration: 320
        easing.type: Easing.InOutSine
      }
    }
  }

  component SourceTab: Item {
    id: tab

    required property string label
    required property string iconText
    required property color accent
    required property bool selected
    required property bool playing

    signal clicked()

    readonly property int horizontalPadding: Style.space(8)

    implicitWidth: tabContent.implicitWidth + horizontalPadding * 2
    implicitHeight: Style.space(28)
    activeFocusOnTab: true
    Keys.onReturnPressed: tab.clicked()
    Keys.onEnterPressed: tab.clicked()
    Keys.onSpacePressed: tab.clicked()

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: tabMouse.containsMouse || tab.activeFocus ? root.panelFill : "transparent"

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Row {
      id: tabContent
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        textFormat: Text.PlainText
        text: tab.iconText
        color: tab.accent
        font.family: root.fontFamily
        font.pixelSize: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: tab.label
        color: tab.selected ? root.foreground : root.panelMuted
        font.family: root.panelFontFamily
        font.pixelSize: Style.space(11)
        anchors.verticalCenter: parent.verticalCenter
      }

      PlaybackEqualizer {
        anchors.verticalCenter: parent.verticalCenter
        accent: tab.accent
        visible: root.showEqualizer
        playing: root.showEqualizer && tab.playing
        showIdle: true
      }
    }

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(14)
      height: Style.space(2)
      radius: height / 2
      color: Color.accent
      visible: tab.selected
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { tab.forceActiveFocus(); tab.clicked() }
    }
  }


  // ------------------------------------------------------------ album colour
  //
  // The panel wears the cover as its background, and "adaptive" is the whole
  // point: a scrim strong enough for a Daft Punk sleeve of near-white beige
  // would bury a dark one, so the cover is measured and the scrim answers.
  // Two numbers come back — the mean luminance, which sets how hard the scrim
  // has to work, and the dominant colour, which tints it so the panel reads
  // as part of the artwork instead of a window parked on top of it.
  //
  // Qt can show the image but cannot tell us what colour it is, so an
  // ImageMagick probe does the reading. Everything downstream falls back to
  // the plain theme panel while that is unanswered or has failed, which is
  // also what happens on a machine with no ImageMagick at all.
  property string artDominant: ""
  property string artMean: ""
  property real artLuma: 0
  // The URL the three values above describe — not necessarily the current
  // one, which is what stops a stale answer from repainting a new track.
  property string artProbed: ""
  property string artProbeError: ""
  // The normalised copy the probe wrote. Everything the panel displays comes
  // from here and never from `artUrl`: a QML Image handed a raw art URL would
  // repeat none of the probe's checks, and Qt would fetch any origin, follow
  // redirects, and decode whatever its image plugins handle -- SVG and PDF
  // included -- inside the shell process.
  property string artFile: ""
  readonly property string artSourceUrl: Model.fileUrl(artFile)

  // Once the displayed cover comes from the probe, there is no configuration
  // in which it is skippable -- turning the backdrop off still leaves the
  // panel's own thumbnail to produce.
  readonly property bool artWanted: true
  // Only true once a cover has actually been measured and drawn.
  readonly property bool backdropActive: artBackground && artFile !== "" && artProbed === artUrl
  readonly property real scrimStrength: Model.scrimAlpha(artLuma, artIntensity)
  readonly property real artBrightness: Model.artBrightness(artLuma)

  // Theme panel colour pushed a fifth of the way towards the cover, at
  // whatever opacity the cover's brightness demands. Tinting the theme colour
  // rather than replacing it is what keeps a dark theme dark and a light one
  // light while still letting the album through.
  readonly property color scrimColor: {
    var base = Color.popups.background
    if (artDominant === "" || !artBackground) return Qt.rgba(base.r, base.g, base.b, artBackground ? scrimStrength : 1.0)
    var dominant = Qt.color(artDominant)
    var mixed = Qt.tint(base, Qt.rgba(dominant.r, dominant.g, dominant.b, 0.20))
    return Qt.rgba(mixed.r, mixed.g, mixed.b, scrimStrength)
  }

  onArtUrlChanged: artProbeDelay.restart()
  onArtWantedChanged: if (artWanted) probeArt(false)
  Component.onCompleted: {
    Qt.callLater(function() { root.chooseInitialSource() })
    probeArt(false)
  }

  function probeArt(force) {
    if (!artWanted) return

    var target = Model.artProbeTarget(root.artUrl)
    if (!target) {
      root.forgetArt()
      return
    }
    if (!force && root.artProbed === root.artUrl) return

    // A skipped-through queue can outrun the probe; the last URL wins.
    if (artProbe.running) artProbe.running = false
    artProbe.pending = root.artUrl
    artProbe.command = ["/bin/sh", "-c", Model.artProbeScript(), "sh", target]
    artProbe.running = true
  }

  function forgetArt() {
    root.artFile = ""
    root.artDominant = ""
    root.artMean = ""
    root.artLuma = 0
    root.artProbed = ""
  }

  function applyArtProbe(url, text) {
    // A probe that finished after the track already moved on describes the
    // wrong cover, so drop it and let the newer one land.
    if (url !== root.artUrl) return

    var probe = Model.parseArtProbe(text)
    if (!probe) {
      root.artProbeError = "no colour in probe output"
      return
    }

    root.artProbeError = ""
    root.artFile = probe.file
    root.artDominant = probe.dominant
    root.artMean = probe.mean
    root.artLuma = probe.luma
    root.artProbed = url
  }

  // Track changes arrive in bursts while skipping; only the settled one is
  // worth a subprocess and a download.
  Timer {
    id: artProbeDelay
    interval: 250
    onTriggered: root.probeArt(false)
  }

  Process {
    id: artProbe
    property string pending: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyArtProbe(artProbe.pending, text)
    }

    onExited: function(exitCode) {
      // The collector still fires on failure, with nothing in it; this is
      // only here so the reason survives for `artDebug`.
      if (exitCode !== 0) root.artProbeError = "probe exited " + exitCode
    }
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
    if (!live || !player.canGoNext) return false
    player.next()
    return true
  }

  function skipPrevious() {
    if (!live || !player.canGoPrevious) return false
    player.previous()
    return true
  }

  function seekTo(seconds) {
    if (!canSeek) return false
    player.position = Math.max(0, Math.min(trackLength, seconds))
    return true
  }

  function nudgeVolume(delta) {
    if (!live || !player.volumeSupported) return false
    player.volume = Math.max(0, Math.min(1, player.volume + delta))
    return true
  }

  function toggleShuffle() {
    if (!live || !player.shuffleSupported) return false
    player.shuffle = !player.shuffle
    return true
  }

  function cycleLoop() {
    if (!live || !player.loopSupported) return false
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
        youtubeLaunch.command = Preferences.youtubeLaunch(root.settings)
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
      if (exitCode !== 0) {
        root.settingsError = root.tr("Could not start browser.") + " " + launchError.text.trim()
        root.openSettings()
      }
    }
  }

  function statusJson() {
    return JSON.stringify({
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
      position: root.trackPosition,
      length: root.trackLength,
      shuffle: root.shuffleOn,
      loop: root.loopName,
      leftClick: root.leftClick,
      language: root.language,
      editingSettings: root.editingSettings,
      artDominant: root.artDominant,
      artLuma: root.artLuma,
      revision: 10
    })
  }

  // ---------------------------------------------------------------- bar entry
  visible: shown
  readonly property real labelSlot: labelClip.visible ? labelClip.width + Style.space(6) : 0
  readonly property real equalizerSlot: barEqualizer.visible
    ? barEqualizer.implicitWidth + Style.space(6)
    : 0
  implicitWidth: !shown ? 0 : (vertical
    ? barSize
    : Math.round(glyph.implicitWidth + labelSlot + equalizerSlot + Style.space(12)))
  implicitHeight: !shown ? 0 : (vertical ? Math.round(glyph.implicitHeight + Style.space(10)) : barSize)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.vertical ? 0 : Style.space(6)

    Text {
      textFormat: Text.PlainText
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.sourceIcon
      color: !root.live ? Qt.darker(root.barForeground, 1.9)
        : root.playing ? root.accentColor
        : Qt.darker(root.accentColor, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: labelClip
      visible: !root.vertical && root.label !== ""
      width: visible ? Math.min(root.maxLabelWidth, labelText.implicitWidth) : 0
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      // The title sits at the start and stays readable. Only a title too long
      // for the slot pans, and it rests at both ends before turning around,
      // so glancing at the bar always catches the beginning of a track.
      Text {
        textFormat: Text.PlainText
        id: labelText
        text: root.label
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        x: -panOffset

        property real panOffset: 0
        readonly property real overflow: Math.max(0, implicitWidth - labelClip.width)

        onTextChanged: {
          panOffset = 0
          if (marquee.running) marquee.restart()
        }
      }

      SequentialAnimation {
        id: marquee
        running: root.animateTitle && labelText.overflow > 0 && labelClip.visible && !root.opened
        loops: Animation.Infinite
        onRunningChanged: if (!running) labelText.panOffset = 0

        PauseAnimation { duration: 2600 }
        NumberAnimation {
          target: labelText
          property: "panOffset"
          from: 0
          to: labelText.overflow
          duration: Math.max(1600, labelText.overflow * 45)
          easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: 2200 }
        NumberAnimation {
          target: labelText
          property: "panOffset"
          from: labelText.overflow
          to: 0
          duration: Math.max(900, labelText.overflow * 20)
          easing.type: Easing.InOutQuad
        }
      }
    }

    PlaybackEqualizer {
      id: barEqualizer
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showEqualizer && !root.vertical && root.live
      accent: root.accentColor
      playing: root.showEqualizer && root.playing
      showIdle: true
    }
  }

  // Thin now-playing underline along the bottom of the widget.
  Rectangle {
    id: progressLine
    visible: root.showProgress && root.live && root.trackLength > 0 && !root.vertical
    x: Style.space(6)
    width: Math.max(0, (root.width - Style.space(12)) * root.progress)
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: root.accentColor
    opacity: root.playing ? 0.95 : 0.5
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2)

    Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  // The bar overlays every widget slot with its own pointer handler for
  // drag-to-reorder. It forwards a left click only to a slot that exposes
  // triggerPress(), and that same check drives the pointer cursor and the
  // open-panel indicator, so the click policy has to live here rather than in
  // a MouseArea of our own. Buttons the bar does not accept still fall
  // through to the MouseArea below, which routes them back to this function.
  function triggerPress(button) {
    if (bar) bar.hideTooltip(root)

    var name = button === Qt.LeftButton ? "left" : button === Qt.RightButton ? "right"
      : button === Qt.MiddleButton ? "middle" : ""
    var action = Preferences.clickAction(name, root.leftClick)
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

    property var wheelTrace: []

    function recordWheel(wheel, outcome) {
      var trace = pointer.wheelTrace.slice(-11)
      trace.push({
        phase: wheel.phase,
        angle: wheel.angleDelta.y,
        pixel: wheel.pixelDelta.y,
        accumulated: Math.round(pointer.wheelAccumulator),
        outcome: outcome
      })
      pointer.wheelTrace = trace
    }

    function endGesture() {
      pointer.wheelAccumulator = 0
      pointer.gestureSkipped = false
    }

    onClicked: function(mouse) { root.triggerPress(mouse.button) }

    onWheel: function(wheel) {
      if (!root.live || root.scrollAction === "Nothing") {
        pointer.recordWheel(wheel, "ignored")
        return
      }

      // Kinetic scrolling after the fingers lift is not a deliberate request.
      if (wheel.phase === pointer.phaseMomentum) {
        pointer.recordWheel(wheel, "momentum")
        return
      }

      if (wheel.phase === pointer.phaseBegin) pointer.endGesture()
      if (wheel.phase === pointer.phaseEnd) {
        pointer.recordWheel(wheel, "gesture-end")
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
        // Volume is meant to be continuous, so every step counts on both kinds
        // of device — just scaled so a swipe is not a jump to the extremes.
        var volumeStep = continuous ? pointer.notch * 2 : pointer.notch
        while (Math.abs(pointer.wheelAccumulator) >= volumeStep) {
          var volumeUp = pointer.wheelAccumulator > 0
          pointer.wheelAccumulator += volumeUp ? -volumeStep : volumeStep
          root.nudgeVolume((volumeUp ? 1 : -1) * root.volumeStep / 100)
        }
        pointer.recordWheel(wheel, "volume")
        return
      }

      if (continuous) {
        if (pointer.gestureSkipped || Math.abs(pointer.wheelAccumulator) < pointer.gestureThreshold) {
          pointer.recordWheel(wheel, pointer.gestureSkipped ? "gesture-consumed" : "accumulating")
          return
        }

        pointer.gestureSkipped = true
        var swipeUp = pointer.wheelAccumulator > 0
        pointer.recordWheel(wheel, swipeUp ? "previous" : "next")
        if (swipeUp) root.skipPrevious()
        else root.skipNext()
        return
      }

      // Discrete wheel: one skip per notch, rate limited so a fast spin does
      // not tear through the queue.
      if (Math.abs(pointer.wheelAccumulator) < pointer.notch) {
        pointer.recordWheel(wheel, "accumulating")
        return
      }

      var up = pointer.wheelAccumulator > 0
      pointer.wheelAccumulator = 0

      if (skipCooldown.running) {
        pointer.recordWheel(wheel, "cooldown")
        return
      }

      skipCooldown.restart()
      pointer.recordWheel(wheel, up ? "previous" : "next")
      if (up) root.skipPrevious()
      else root.skipNext()
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.live ? ((root.playing ? "" : root.tr("Paused") + " — ") + Model.barLabel(root.player, true)) : root.sourceName + " — " + root.tr("Not running"))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Timer {
    id: gestureIdle
    interval: 220
    repeat: false
    onTriggered: pointer.endGesture()
  }

  Timer {
    id: skipCooldown
    interval: 350
    repeat: false
  }

  // MPRIS position is only re-read when something asks for it, so drive a
  // re-read while there is a progress display that would otherwise go stale.
  Timer {
    running: root.playing && (root.opened || progressLine.visible)
    interval: root.opened ? 500 : 1000
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // Use a card-width anchor to align the popup with the widget's left edge.
  // Vertical bars keep the stock centring geometry.
  Item {
    id: popupLeftAnchor
    x: 0
    y: 0
    width: popup.contentWidth
    height: root.height
  }

  // ------------------------------------------------------------------ popup
  component MediaLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.panelFontFamily
    font.pixelSize: Style.space(13)
  }

  component MediaControl: Button {
    width: Style.space(36)
    height: Style.space(36)
    horizontalPadding: 0
    verticalPadding: 0
    radius: Style.space(7)
    fontFamily: root.fontFamily
    iconSize: Style.space(18)
    foreground: root.foreground
    accent: Color.accent
    focusable: true
    opacity: enabled ? 1 : 0.35
  }

  component MediaToggle: MediaControl {
    property bool toggledOn: false

    // Mode state stays visible independently of pointer and keyboard focus.
    foreground: toggledOn && enabled ? Color.popups.background : root.panelMuted
    color: toggledOn && enabled ? Color.accent : hot && enabled ? root.panelFill : "transparent"
    borderSpec: activeFocus && enabled
      ? Border.flat(root.foreground, Math.max(1, Style.space(1))) : Border.none()
  }

  MediaPopup {
    id: popup
    anchorItem: root.vertical ? root : popupLeftAnchor
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: root.editingSettings ? settingsPane.backTarget : settingsButton
    padding: 0
    borderSpec: Border.flat(root.panelOutline, 1)
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, root.editingSettings ? Style.space(620) : 0)

    // Settings and short displays share the same bounded scrolling surface.
    Flickable {
      id: mediaScroll
      Connections {
        target: mediaScroll.Window.window
        function onActiveFocusItemChanged() {
          var item = target.activeFocusItem
          if (!root.editingSettings || !item) return
          var point = item.mapToItem(mediaScroll.contentItem, 0, 0)
          if (point.y < mediaScroll.contentY) mediaScroll.contentY = Math.max(0, point.y - Style.space(8))
          else if (point.y + item.height > mediaScroll.contentY + mediaScroll.height)
            mediaScroll.contentY = Math.min(mediaScroll.contentHeight - mediaScroll.height,
              point.y + item.height - mediaScroll.height + Style.space(8))
        }
      }
      Keys.onEscapePressed: root.editingSettings ? root.closeSettings() : root.close()
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      interactive: contentHeight > height + 1
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      // A source can lose its track while the compact player is scrolled.
      onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
      onHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
      Controls.ScrollBar.vertical: Controls.ScrollBar {
        visible: mediaScroll.interactive
        width: Style.space(4)
        padding: 0
        contentItem: Rectangle { implicitWidth: Style.space(4); radius: width / 2; color: root.panelMuted }
        background: Item {}
      }

      Column {
        id: column
        width: parent.width

        SettingsPane {
          id: settingsPane
          visible: root.editingSettings
          width: parent.width
          settings: root.settings
          language: root.language
          saving: preferencesSave.running
          error: root.settingsError
          onClearError: root.settingsError = ""
          onSave: function(key, value) { root.savePreference(key, value) }
          onBack: root.closeSettings()
        }

        Item {
          id: header
          visible: !root.editingSettings
          width: parent.width
          height: headerContent.implicitHeight + Style.space(root.compactPanel ? 30 : 42)
          // Confine the blur to the header, with only the outer top corners rounded.
          layer.enabled: true
          layer.effect: MultiEffect { maskEnabled: true; maskSource: headerClipMask }
          Item {
            id: headerClipMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; radius: Style.space(13); color: "white" }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: "white" }
          }

          // The measured cover supplies only the header wash. Controls below
          // stay on the same plain surface as the clock and weather panels.
          Item {
            id: backdrop
            z: -1
            anchors.fill: parent
            visible: root.artBackground

            // The card is rounded outside its border; inside it, the corner is
            // that much tighter. Zero on a theme with square corners, which is
            // also where the mask below turns itself off.
            readonly property real corner: Math.max(0, popup.cornerRadius - Border.top(popup.borderSpec))

            // Blurring samples past the edges of its source, so an image stopping
            // at the card would fade to nothing around the rim. The cover is drawn
            // larger than the card instead and the mask below cuts it back, which
            // puts the fade safely outside.
            readonly property real bleed: Style.space(32)

            Image {
              id: artSource
              anchors.fill: parent
              anchors.margins: -backdrop.bleed
              source: root.artBackground ? root.artSourceUrl : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              // Drawn only through the effect below, never directly.
              visible: false
              // A fixed decode size, not one bound to the item's own width, which
              // would re-decode the image every time the popup resizes. The blur
              // erases anything finer than this long before it reaches the screen.
              sourceSize.width: 384
              sourceSize.height: 384
            }

            // Blurred hard, desaturated a little, and dimmed by however bright the
            // cover measured. The blur is what turns a photograph into a texture:
            // no edge in it competes with the text sitting on top.
            MultiEffect {
              anchors.fill: artSource
              source: artSource
              blurEnabled: true
              blur: 1.0
              blurMax: 48
              blurMultiplier: 1.6
              saturation: 0.2
              // Flattening the cover's own contrast a little is worth more to the
              // text on top than it costs the artwork underneath: it is the bright
              // patches, not the average, that swallow a caption.
              contrast: -0.1
              brightness: root.artBrightness
              maskEnabled: true
              maskSource: cornerMask
              // Without a threshold the mask's transparent margin still passes, and
              // the blur spills out over the card's border.
              maskThresholdMin: 0.5
              maskSpreadAtMin: 0.05
              // Fades out while the next cover loads and back in when it is ready,
              // so a track change is a crossfade rather than a flash of theme.
              opacity: artSource.status === Image.Ready ? 1 : 0
              visible: opacity > 0

              Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
              }
            }

            // Matches the effect's geometry exactly, and marks the card-sized
            // rectangle inside it as the only part that survives. The lower
            // corners meet the controls inside the card and must stay square.
            Item {
              id: cornerMask
              anchors.fill: artSource
              layer.enabled: true
              visible: false

              Rectangle {
                anchors.fill: parent
                anchors.margins: backdrop.bleed
                radius: backdrop.corner
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: "black"
              }
            }

            // The legibility scrim, and the adaptive half of this whole feature:
            // theme panel colour, tinted towards the cover, at the opacity the
            // cover's brightness calls for. Text contrast stays where the theme
            // put it no matter what is playing.
            Rectangle {
              anchors.fill: parent
              radius: backdrop.corner
              bottomLeftRadius: 0
              bottomRightRadius: 0
              color: root.scrimColor

              Behavior on color {
                ColorAnimation { duration: 280; easing.type: Easing.OutCubic }
              }
            }
          }

          Column {
            id: headerContent
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(root.compactPanel ? 20 : 30)


            Row {
              width: parent.width
              spacing: Style.space(18)

              Rectangle {
                id: art
                width: Math.min(Style.space(root.compactPanel ? 96 : 128), parent.width * 0.34)
                height: width
                radius: Style.space(8)
                color: root.panelFill
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: artworkMask }

                Image {
                  id: coverImage
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  source: root.artSourceUrl
                  visible: status === Image.Ready
                }
                MediaLabel {
                  anchors.centerIn: parent
                  visible: coverImage.status !== Image.Ready
                  text: root.sourceIcon
                  color: root.sourceBrandColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(36)
                }
              }
              Item {
                id: artworkMask
                width: art.width
                height: art.height
                visible: false
                layer.enabled: true
                layer.textureSize: Qt.size(art.width, art.height)
                Rectangle { width: art.width; height: art.height; radius: art.radius; color: "white" }
              }

              Column {
                width: parent.width - art.width - parent.spacing
                anchors.bottom: parent.bottom
                spacing: Style.space(5)
                MediaLabel {
                  width: parent.width
                  text: root.live ? (root.trackTitle || root.tr("Nothing playing"))
                    : root.sourceOpen ? root.tr("Nothing playing") : root.sourceName + " — " + root.tr("Not running")
                  font.pixelSize: Style.space(root.compactPanel ? 20 : 24)
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
                MediaLabel {
                  width: parent.width
                  text: root.trackArtist
                  font.pixelSize: Style.space(14)
                  color: root.panelMuted
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  visible: text !== ""
                }
                MediaLabel {
                  width: parent.width
                  text: root.trackAlbum
                  font.pixelSize: Style.space(12)
                  color: root.panelMuted
                  elide: Text.ElideRight
                  visible: text !== ""
                }
              }
            }
          }
        }

        Column {
          id: controlBody
          visible: !root.editingSettings
          width: parent.width - Style.space(40)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(12)
          Item { width: 1; height: Style.space(8) }

          Column {
            width: parent.width
            spacing: Style.space(1)
            visible: root.live && root.trackLength > 0
            PanelSlider {
              id: seekSlider
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: Math.max(1, root.trackLength)
              value: root.trackPosition
              step: 5
              trackColor: root.panelFill
              fillColor: Color.accent
              knobColor: Color.accent
              knobSize: Style.space(10)
              enabled: root.canSeek
              opacity: root.canSeek ? 1 : 0.5
              onReleased: function(value) { root.seekTo(value) }
            }
            Item {
              width: parent.width
              height: elapsedText.implicitHeight
              MediaLabel {
                id: elapsedText
                anchors.left: parent.left
                text: Model.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.trackPosition)
                font.pixelSize: Style.space(11)
                color: root.panelMuted
              }
              MediaLabel {
                anchors.right: parent.right
                text: Model.formatTime(root.trackLength)
                font.pixelSize: Style.space(11)
                color: root.panelMuted
              }
            }
          }

          Row {
            id: transportControls
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(Style.space(8), (controlBody.width - Style.space(216)) / 4)
            visible: root.live
            MediaToggle {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒝"
              toggledOn: root.shuffleOn
              tooltipText: root.tr(root.shuffleOn ? "Shuffle on" : "Shuffle off")
              enabled: root.sourceKind === "spotify" && root.live && root.player.shuffleSupported
              onClicked: root.toggleShuffle()
            }
            MediaControl {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒮"
              tooltipText: root.tr("Previous track")
              enabled: root.live && root.player.canGoPrevious
              onClicked: root.skipPrevious()
            }
            MediaControl {
              id: playPauseButton
              width: Style.space(48)
              height: width
              radius: width / 2
              iconText: root.playing ? "󰏤" : "󰐊"
              iconSize: Style.space(23)
              foreground: Color.popups.background
              background: root.foreground
              color: hot || activeFocus ? Color.accent : root.foreground
              tooltipText: root.tr(root.playing ? "Pause" : "Play")
              enabled: root.live
              onClicked: root.playPause()
            }
            MediaControl {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒭"
              tooltipText: root.tr("Next track")
              enabled: root.live && root.player.canGoNext
              onClicked: root.skipNext()
            }
            MediaToggle {
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.loopIcon
              toggledOn: root.loopState !== MprisLoopState.None
              tooltipText: root.tr(root.loopState === MprisLoopState.Track ? "Repeat: track" : root.loopState === MprisLoopState.Playlist ? "Repeat: playlist" : "Repeat: off")
              enabled: root.sourceKind === "spotify" && root.live && root.player.loopSupported
              onClicked: root.cycleLoop()
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)
            visible: root.live && root.player.volumeSupported
            MediaLabel {
              width: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              text: root.live && root.player.volume < 0.01 ? "󰝟" : "󰕾"
              font.family: root.fontFamily
              color: root.panelMuted
              horizontalAlignment: Text.AlignHCenter
            }
            PanelSlider {
              id: volumeSlider
              width: parent.width - Style.space(71)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.live ? root.player.volume : 0
              trackColor: root.panelFill
              fillColor: Color.accent
              knobColor: Color.accent
              knobSize: Style.space(10)
              onMoved: function(value) { if (root.live) root.player.volume = value }
            }
            MediaLabel {
              width: Style.space(31)
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(volumeSlider.liveValue * 100) + "%"
              font.pixelSize: Style.space(11)
              color: root.panelMuted
              horizontalAlignment: Text.AlignRight
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.panelOutline }
          Item {
            id: mediaFooter
            width: parent.width
            height: Style.space(28)
            Row {
              id: sourceTabRow
              spacing: Style.space(4)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              SourceTab {
                visible: root.spotifyOpen || !root.anySourceOpen
                enabled: root.spotifyOpen
                label: "Spotify"
                iconText: ""
                selected: root.sourceKind === "spotify"
                accent: root.spotifyGreen
                playing: root.spotifyPlaying
                onClicked: root.selectSource("spotify")
              }
              SourceTab {
                visible: root.youtubeOpen
                label: "YouTube"
                iconText: ""
                selected: root.sourceKind === "youtube"
                accent: root.youtubeRed
                playing: root.youtubePlaying
                onClicked: root.selectSource("youtube")
              }
            }

            PanelActionButton {
              id: settingsButton
              anchors.right: launchButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(26)
              iconText: "󰒓"
              fontFamily: root.fontFamily
              fontSize: Style.space(16)
              foreground: root.panelMuted
              focusable: true
              tooltipText: root.tr("Settings")
              onClicked: root.openSettings()
            }
            PanelActionButton {
              id: launchButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(26)
              iconText: "󰏌"
              fontFamily: root.fontFamily
              fontSize: Style.space(14)
              foreground: root.panelMuted
              focusable: true
              tooltipText: root.tr(root.sourceOpen ? "Show" : "Start") + " " + root.sourceName
              onClicked: { root.launch(); root.close() }
            }
          }

          Item { width: 1; height: Style.space(1) }
        }
      }
    }
  }

  IpcHandler {
    target: "foamy.media"

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
    function status(): string { return root.statusJson() }
    function wheelDebug(): string { return JSON.stringify(pointer.wheelTrace) }
    function artDebug(): string {
      return JSON.stringify({
        wanted: root.artWanted,
        file: root.artFile,
        url: root.artUrl,
        target: Model.artProbeTarget(root.artUrl),
        probed: root.artProbed,
        running: artProbe.running,
        error: root.artProbeError,
        mean: root.artMean,
        dominant: root.artDominant,
        luma: root.artLuma,
        scrim: root.scrimStrength,
        brightness: root.artBrightness,
        imageStatus: artSource.status
      })
    }
    function reprobeArt(): void { root.probeArt(true) }
  }
}
