import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../kit"
import ".." as Media

// Mock states for the foamy-kit preview harness (no MPRIS, no processes).
// The harness sets bar/anchorItem, then cycles previewState and captures
// `popup`. The bar widget (BarContent) is drawn on the simulated bar strip
// next to the harness anchor, so the 4.5 screen shots show it too.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["playing", "two-sources", "not-running", "settings", "settings-browser"]
  property string previewState: "playing"
  property int settleMs: 900
  readonly property Item popup: popup

  QtObject {
    id: mock
    readonly property string state: preview.previewState
    readonly property bool idle: state === "not-running"
    readonly property bool youtube: state === "two-sources"
    readonly property QtObject bar: preview.bar
    property bool opened: true
    readonly property bool editingSettings: state.indexOf("settings") === 0
    readonly property bool browserSettingsOpen: state === "settings-browser"
    readonly property bool compactPanel: false
    readonly property bool live: !idle
    readonly property bool playing: state === "playing"
    readonly property string sourceKind: youtube ? "youtube" : "spotify"
    readonly property string sourceName: youtube ? "YouTube" : "Spotify"
    readonly property string sourceIcon: youtube ? "" : ""
    readonly property bool sourceOpen: !idle
    readonly property bool spotifyOpen: !idle
    readonly property bool youtubeOpen: youtube
    readonly property bool anySourceOpen: !idle
    readonly property bool spotifyPlaying: state === "playing" || youtube
    readonly property bool youtubePlaying: false
    readonly property string trackTitle: idle ? "" : youtube ? "Building a tiny synthesizer from scratch" : "A Quiet Morning"
    readonly property string trackArtist: idle ? "" : youtube ? "Sound Lab" : "Example Artist"
    readonly property string trackAlbum: idle || youtube ? "" : "Demo Album"
    readonly property real trackLength: youtube ? 1124 : 240
    readonly property real trackPosition: youtube ? 431 : 85
    readonly property bool canSeek: true
    readonly property bool canGoPrevious: true
    readonly property bool canGoNext: true
    readonly property bool shuffleSupported: !youtube
    readonly property bool loopSupported: !youtube
    readonly property bool volumeSupported: !idle
    readonly property real volume: 0.65
    readonly property bool shuffleOn: true
    readonly property string loopName: "off"
    readonly property string artSource: idle || youtube ? "" : Qt.resolvedUrl("cover.png")
    readonly property string artDominant: artSource ? "#4e4376" : ""
    readonly property real artLuma: 0.22
    readonly property bool artBackground: true
    readonly property int artIntensity: 55
    readonly property bool showEqualizer: true
    readonly property color spotifyGreen: "#1DB954"
    readonly property color youtubeRed: "#FF0033"
    readonly property color sourceBrandColor: youtube ? youtubeRed : spotifyGreen
    readonly property var settings: ({ id: "foamy.media", youtubeAppId: "vivaldi-youtube.com__-Default", youtubeProfile: "Default" })
    readonly property bool saving: false
    property string settingsError: ""
    readonly property var lastSave: null
    readonly property var browserCandidates: browserSettingsOpen ? [{
      id: "vivaldi-youtube.com__-Default", title: "YouTube",
      values: { youtubeAppId: "vivaldi-youtube.com__-Default", youtubeProfile: "Default", youtubeBrowser: "vivaldi", youtubeMprisName: "vivaldi" }
    }, {
      id: "chromium-youtube.com__-Profile_2", title: "YouTube – Work",
      values: { youtubeAppId: "chromium-youtube.com__-Profile_2", youtubeProfile: "Profile 2", youtubeBrowser: "chromium" }
    }] : []
    function playPause() {}
    function skipNext() {}
    function skipPrevious() {}
    function seekTo(s) {}
    function seekBy(s) {}
    function setVolume(v) {}
    function toggleShuffle() {}
    function cycleLoop() {}
    function selectSource(k) {}
    function launch() {}
    function openSettings() {}
    function closeSettings() {}
    function close() {}
    function switchPanel(d) {}
    function save(k, v) {}
    function saveMany(v) {}
    function retrySave() {}
  }

  // The bar widget on the strip, covering the harness anchor icon.
  Rectangle {
    parent: preview.anchorItem.parent
    z: 1
    x: preview.anchorItem.x - 4
    y: barWidget.y
    width: barWidget.width + 8
    height: barWidget.height
    color: Commons.Color.bar.background
  }
  Media.BarContent {
    id: barWidget
    parent: preview.anchorItem.parent
    z: 2
    x: preview.anchorItem.x
    y: preview.anchorItem.y + preview.anchorItem.height / 2 - height / 2
    width: implicitWidth
    height: implicitHeight
    barSize: preview.bar.barSize
    fontFamily: Style.font.family
    glyph: mock.sourceIcon
    glyphColor: !mock.live ? Qt.darker(Commons.Color.bar.text, 1.9) : mock.playing ? mock.sourceBrandColor : Qt.darker(mock.sourceBrandColor, 1.5)
    label: mock.live ? mock.trackTitle + " — " + mock.trackArtist : ""
    labelColor: Commons.Color.bar.text
    live: mock.live
    playing: mock.playing
    accent: mock.sourceBrandColor
    progress: mock.trackPosition / mock.trackLength
    // Shots show the popup open, where the open-panel mark replaces the underline.
    popupOpen: mock.opened
  }
  // Where the 4.5 bar draws its open-panel mark (inner edge, 55% wide):
  // the underline is hidden while the popup is open, so the two never overlap.
  Rectangle {
    parent: preview.anchorItem.parent
    z: 3
    visible: preview.bar.position === "top"
    width: Math.round(barWidget.width * 0.55)
    height: 2
    radius: 1
    x: barWidget.x + Math.floor(barWidget.width / 2 - width / 2)
    y: preview.bar.barSize - height - 2
    color: Commons.Color.accent
    opacity: 0.9
  }
  // The same widget with its popup closed: the progress underline shows.
  Media.BarContent {
    id: closedWidget
    parent: preview.anchorItem.parent
    z: 1
    x: preview.anchorItem.x - 420
    y: barWidget.y
    width: implicitWidth
    height: implicitHeight
    barSize: preview.bar.barSize
    fontFamily: Style.font.family
    glyph: barWidget.glyph
    glyphColor: barWidget.glyphColor
    label: barWidget.label
    labelColor: barWidget.labelColor
    live: mock.live
    playing: mock.playing
    accent: mock.sourceBrandColor
    progress: barWidget.progress
    popupOpen: false
  }
  Item {
    id: popupLeftAnchor
    parent: preview.anchorItem.parent
    x: barWidget.x
    y: barWidget.y
    width: popup.contentWidth
    height: barWidget.height
  }

  // Scroll the settings page to the browser picker for that shot.
  onPreviewStateChanged: if (previewState === "settings-browser") scrollToBrowser.start()
  Timer {
    id: scrollToBrowser
    interval: 300
    onTriggered: {
      var view = popup.bodyItem
      if (view && view.settingsPage && view.settingsPage.browserSection)
        view.settingsPage.keepVisible(view.settingsPage.browserSection)
    }
  }

  FoamyPopup {
    id: popup
    anchorItem: popupLeftAnchor
    bar: preview.bar
    open: true
    body: Component {
      Media.MediaView { media: mock }
    }
  }
}
