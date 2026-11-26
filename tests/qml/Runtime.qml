import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "harness"
import "plugin" as Media
import "plugin/kit"
import "plugin/kit/FoamyPrefs.js" as Prefs
import "plugin/BrowserSetup.js" as BrowserSetup

// Foamy Media under a real host shell, offscreen: three bar instances (as on
// three monitors) sharing one MediaService and one leader, the lazy popup
// body, the single keyboard cursor, settings saving through the bar, an art
// probe that cannot start, the equalizer and marquee gates, translations and
// RTL mirroring, and YouTube being focus-only. No MPRIS player is reachable
// here, so the widget is in its "not running" state; the English run
// (FOAMY_HINT=1) then drives clicks, source selection, the position tick,
// the wheel and the transport with stand-in players, and the window picker's
// hint. The entry still holds the browser and profile keys 1.3.3 and earlier
// saved, which must stay inert. tests/art-runtime.py covers the cover service.
ShellRoot {
  id: shell
  readonly property string host: Quickshell.env("FOAMY_HOST")
  readonly property string lang: Quickshell.env("FOAMY_LANG") || "en"
  readonly property bool v45: host === "4.5"
  property int checks: 0
  property int failures: 0

  function check(ok, label) {
    checks++
    if (!ok) {
      failures++
      console.log("FOAMY FAIL " + host + "/" + lang + " " + label)
    }
  }
  function eq(actual, expected, label) {
    check(actual === expected, label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
  }

  FloatingWindow {
    implicitWidth: 1920
    implicitHeight: 1080
    color: "black"
    ScreenSim {
      id: sim
    }
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
          settings: ({
              id: "foamy.media",
              hideWhenClosed: false,
              extra: "kept",
              youtubeBrowser: "chromium",
              youtubeProfile: "Profile 2"
            })
        }
      }
    }
    // Presentation pieces, fed directly.
    Media.Equalizer {
      id: equalizer
      playing: true
      animate: true
    }
    // Mirrored as the host's popup card mirrors its body, so the RTL run
    // reaches the mirrored path.
    Item {
      y: 120
      width: 420
      height: playerView.height
      LayoutMirroring.enabled: FoamyI18n.rightToLeft
      LayoutMirroring.childrenInherit: true
      Media.MediaView {
        id: playerView
        width: parent.width
        media: player
      }
    }
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
    Media.BarContent {
      id: growBar
      y: 90
      label: "X"
      maxLabelWidth: 600
      live: true
      playing: true
    }
    // The window picker fed what BrowserSetup makes of two windows: Omarchy's
    // Chromium web app with its player, and a Vivaldi one with none.
    Media.BrowserPicker {
      id: picker
      x: 1000
      y: 120
      width: 400
      settings: ({
          id: "foamy.media"
        })
      candidates: BrowserSetup.candidates([
        {
          appId: "chrome-youtube.com__-Default",
          title: "A - YouTube"
        },
        {
          appId: "vivaldi-youtube.com__-Default",
          title: "B - YouTube"
        }
      ], [
        {
          dbusName: "org.mpris.MediaPlayer2.chromium.instance4242"
        }
      ])
    }
  }

  MockBar {
    id: mockBar
    moduleName: "foamy.media"
    // The commands the widget hands the bar to run.
    property var ran: []
    function run(command) {
      ran = ran.concat([String(command)])
    }
  }

  // A playing player for the cursor checks (MediaView reads only `media`).
  QtObject {
    id: player
    property var calls: []
    function log(name, value) {
      calls = calls.concat([name + (value === undefined ? "" : ":" + value)])
    }
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
    function playPause() {
      log("playPause")
    }
    function skipNext() {
      log("next")
    }
    function skipPrevious() {
      log("previous")
    }
    function seekTo(s) {
      log("seekTo", s)
    }
    function seekBy(s) {
      log("seekBy", s)
    }
    function setVolume(v) {
      log("volume", Math.round(v * 100))
    }
    function toggleShuffle() {
      log("shuffle")
    }
    function cycleLoop() {
      log("loop")
    }
    function selectSource(k) {
      log("select", k)
    }
    function launch() {
      log("launch")
    }
    function openSettings() {
      log("settings")
    }
    function closeSettings() {
    }
    function close() {
      log("close")
    }
    function switchPanel(d) {
      log("switch", d)
    }
  }

  Component.onCompleted: Qt.callLater(stepOne)

  FoamyCursor {
    id: keys
  }
  function findKey(item, key) {
    if (!item)
      return null
    if (item.key === key && item.commitEdit !== undefined)
      return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = findKey(kids[i], key)
      if (hit)
        return hit
    }
    return null
  }
  function key(view, text) {
    keys.emitTextKey(view, text)
  }
  function findNamed(item, name) {
    if (!item)
      return null
    if (item.objectName === name)
      return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = findNamed(kids[i], name)
      if (hit)
        return hit
    }
    return null
  }
  // The settings dropdown with this label.
  function findDropdown(item, label) {
    if (!item)
      return null
    if (item.label === label && item.shownValue !== undefined)
      return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = findDropdown(kids[i], label)
      if (hit)
        return hit
    }
    return null
  }
  // The footer tab of one source ("spotify", "youtube") in a player view.
  function sourceTab(item, kind) {
    if (!item)
      return null
    if (item.key === "tab:" + kind && item.kind === kind)
      return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = sourceTab(kids[i], kind)
      if (hit)
        return hit
    }
    return null
  }
  // The parent a screen reader sees: the nearest ancestor with an
  // accessible role (Qt passes over plain layout items).
  function accessibleParent(item) {
    for (var p = item.parent; p; p = p.parent)
      if (p.Accessible.role !== Accessible.NoRole)
        return p
    return null
  }

  function leader() {
    for (var i = 0; i < 3; i++)
      if (panels.itemAt(i).statusObject().leader)
        return panels.itemAt(i)
    return null
  }
  function leaders() {
    var count = 0
    for (var i = 0; i < 3; i++)
      if (panels.itemAt(i).statusObject().leader)
        count++
    return count
  }

  function stepOne() {
    eq(leaders(), 1, "one leader across three bar instances")
    eq(panels.itemAt(0).member.members, 3, "three members")
    var first = panels.itemAt(0)
    eq(first.live, false, "no player offscreen")
    eq(first.popup.bodyItem, null, "popup body is lazy")
    eq(first.member.demanded, false, "no demand while closed")

    // The picker row says when it found no MPRIS name to save.
    picker.expanded = true
    var pickerRows = []
    function collectRows(item) {
      if (item.modelData !== undefined && item.description !== undefined)
        pickerRows.push(item)
      for (var r = 0; r < (item.children || []).length; r++)
        collectRows(item.children[r])
    }
    collectRows(picker)
    eq(pickerRows.length, 2, "two picker rows")
    if (pickerRows.length === 2) {
      var chromiumRow = pickerRows[0].modelData.title === "A - YouTube" ? pickerRows[0] : pickerRows[1]
      var vivaldiRow = chromiumRow === pickerRows[0] ? pickerRows[1] : pickerRows[0]
      var found = findNamed(chromiumRow, "browserMissingName")
      eq(found !== null && found.visible, false, "no note when the name was found")
      var note = findNamed(vivaldiRow, "browserMissingName")
      check(note !== null, "a row without a player has a missing-name note")
      if (note) {
        eq(note.visible, true, "a row without a player says the name is missing")
        eq(note.text, FoamyI18n.t("No MPRIS name found; set it under Advanced"), "the note's text")
        var noteBottom = note.mapToItem(vivaldiRow, 0, note.height).y
        check(noteBottom <= vivaldiRow.height, "the row grows to fit the note: " + noteBottom + " > " + vivaldiRow.height)
      }
    }
    picker.expanded = false

    // Selection is shared by every bar.
    first.selectSource("spotify")
    Media.MediaService.selectedSource = "youtube"
    eq(panels.itemAt(2).sourceKind, "youtube", "source shared across bars")
    Media.MediaService.selectedSource = "spotify"

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
    // Spotify sends the title before the artist, a frame apart (stepTwo).
    growBar.label = "Time After Time"

    // The cursor over a playing player. Transport and sliders keep their
    // physical direction in RTL, where PanelKeyCatcher reports reading order.
    eq(playerView.LayoutMirroring.enabled, shell.lang === "ar", "the player view mirrors in RTL only")
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
      eq(seekSlider.LayoutMirroring.enabled, false, "the timeline keeps its physical direction")
      eq(volumeSlider.LayoutMirroring.enabled, false, "the volume keeps its physical direction")
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
    if (volumeSlider)
      eq(volumeSlider.hasCursor, true, "the cursor on the volume rings its thumb")
    playerView.moveRequested(physical, 0)
    playerView.moveRequested(0, 1)
    eq(playerView.cursorKey, "tab:spotify", "down reaches the source tabs")
    playerView.moveRequested(1, 0)
    eq(playerView.cursorKey, "tab:youtube", "along the tabs in reading order")
    playerView.activateRequested()
    playerView.tabRequested(1)
    eq(JSON.stringify(player.calls), JSON.stringify(["previous", "seekBy:5", "volume:55", "select:youtube", "switch:1"]), "cursor actions")
    // Screen readers read the source row as a tab list: each tab a page tab
    // named after its source, the open source's tab selected.
    var spotifyTab = sourceTab(playerView, "spotify"), youtubeTab = sourceTab(playerView, "youtube")
    check(spotifyTab !== null && youtubeTab !== null, "both source tabs are shown")
    if (spotifyTab && youtubeTab) {
      var tabList = accessibleParent(spotifyTab)
      eq(tabList ? tabList.Accessible.role : Accessible.NoRole, Accessible.PageTabList, "the source tabs' accessible parent is a tab list (role)")
      check(tabList !== null && accessibleParent(youtubeTab) === tabList, "both source tabs are in the same tab list")
      eq(JSON.stringify([spotifyTab.Accessible.role, youtubeTab.Accessible.role]), JSON.stringify([Accessible.PageTab, Accessible.PageTab]), "each source tab is a page tab (role)")
      eq(JSON.stringify([spotifyTab.Accessible.name, youtubeTab.Accessible.name]), JSON.stringify(["Spotify", "YouTube"]), "each source tab is named after its source")
      eq(JSON.stringify([spotifyTab.Accessible.selected, youtubeTab.Accessible.selected]), JSON.stringify([true, false]), "the open source's tab is selected")
      player.sourceKind = "youtube"
      eq(JSON.stringify([spotifyTab.Accessible.selected, youtubeTab.Accessible.selected]), JSON.stringify([false, true]), "the selected tab follows the open source")
      player.sourceKind = "spotify"
    }
    // The hero band carries the cover as its picture (blurred on the GPU,
    // cover-fitted under the kit scrim on the software renderer).
    var gpu = playerView.effectsAvailable
    eq(gpu, false, "the harness renders in software")
    eq(playerView.band.title, "Spotify", "band title names the source")
    eq(playerView.band.imageSource.toString(), "", "no cover, no picture")
    player.artSource = "file:///tmp/foamy-media-cover.png"
    eq(playerView.band.imageSource.toString(), gpu ? "" : "file:///tmp/foamy-media-cover.png", "cover is the band picture")
    eq(playerView.band.background !== null, gpu, "blurred cover only on the GPU renderer")
    player.artBackground = false
    eq(playerView.band.imageSource.toString(), "", "Artwork background off keeps the foamy wash")
    player.artBackground = true
    player.artSource = ""
    // Short screen: the player scrolls and keeps the cursor row in view.
    var scroll = null
    for (var c = 0; c < playerView.children.length; c++)
      if (playerView.children[c].objectName === "mediaMainScroll")
        scroll = playerView.children[c]
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
    // The footer button never offers to start YouTube (focus-only).
    eq(playerView.launchShows, true, "an open source is shown")
    player.sourceOpen = false
    eq(playerView.launchShows, false, "Spotify not running is started")
    player.sourceKind = "youtube"
    eq(playerView.launchShows, true, "YouTube without its window is never started")
    player.sourceKind = "spotify"
    player.sourceOpen = true

    first.open()
    // Steps wait for the state they check, not a fixed delay (FoamyWait).
    wait.waitFor(function () {
      return first.popup.bodyItem !== null && first.member.demanded
    }, 10000, shell.stepTwo, "the popup body is built on open")
  }

  FoamyWait {
    id: wait
  }

  function stepTwo() {
    var first = panels.itemAt(0)
    var view = first.popup.bodyItem
    eq(first.imagesActive, true, "covers decode while open")
    if (!view) {
      shell.finish()
      return
    }
    eq(view.cursorKey, "", "no cursor highlight on open")
    view.moveRequested(0, 1)
    eq(view.cursorKey, "settings", "first move lands on the first stop when nothing plays")
    view.moveRequested(0, 1)
    eq(view.cursorKey, "tab:spotify", "down reaches the source row")
    view.moveRequested(1, 0)
    eq(view.cursorKey, "launch", "along the source row")
    eq(view.LayoutMirroring.enabled, shell.lang === "ar", "popup body mirrors in RTL only")
    // Arabic has no catalog and falls back to English.
    eq(view.band.meta, shell.lang === "no" ? "Ikke startet" : "Not running", "band status in the UI language")
    eq(first.tooltipText, shell.lang === "no" ? "Spotify er ikke startet" : "Spotify is not running", "hover text in the UI language")
    shell.key(view, "s")
    eq(first.editingSettings, true, "s opens Settings")
    eq(view.blocked, true, "settings page owns the keys")
    // A dropdown pick the settings queue refuses shows the saved choice
    // again at once, not for the dropdown's whole hold. Without a module
    // name the widget has no bar entry, and the queue refuses every save.
    first.moduleName = ""
    var dropdownKeys = ["scrollAction", "accent"]
    for (var d = 0; d < dropdownKeys.length; d++) {
      var dropdown = shell.findDropdown(view.settingsPage, view.settingsPage.label(dropdownKeys[d]))
      check(dropdown !== null, dropdownKeys[d] + ": the dropdown is on the settings page")
      if (!dropdown)
        continue
      var savedChoice = dropdown.value
      dropdown.select(dropdown.options[0].value === savedChoice ? dropdown.options[1].value : dropdown.options[0].value)
      eq(first.settingsError, Prefs.NO_ENTRY, dropdownKeys[d] + ": the queue refuses the pick")
      eq(dropdown.shownValue, savedChoice, dropdownKeys[d] + ": a refused pick shows the saved choice again at once")
    }
    first.moduleName = "foamy.media"
    first.save("showArtist", false)
    eq(mockBar.saved.length, 1, "setting saved inline")
    if (mockBar.saved.length === 1) {
      eq(mockBar.saved[0].id, "foamy.media", "saved to the widget's own entry")
      eq(mockBar.saved[0].settings.showArtist, false, "saved value")
      eq(mockBar.saved[0].settings.extra, "kept", "unknown keys kept")
      // Legacy 1.3.3 keys: carried through a save untouched, never read.
      eq(mockBar.saved[0].settings.youtubeBrowser, "chromium", "legacy browser key kept")
      eq(mockBar.saved[0].settings.youtubeProfile, "Profile 2", "legacy profile key kept")
    }
    eq(first.preference("youtubeBrowser"), undefined, "the legacy browser key is no setting")
    eq(first.preference("youtubeAppId"), "vivaldi-youtube.com__-Default", "a legacy entry reads the app ID default")
    first.saveMany({
      youtubeAppId: "chromium-youtube.com__-Default",
      youtubeMprisName: "chromium"
    })
    eq(mockBar.saved.length, 3, "browser suggestion saved key by key")
    if (mockBar.saved.length === 3) {
      eq(mockBar.saved[2].settings.youtubeAppId, "chromium-youtube.com__-Default", "earlier key kept by the later save")
      eq(mockBar.saved[2].settings.youtubeMprisName, "chromium", "later key")
    }
    first.saveMany({
      youtubeMprisName: "--evil",
      youtubeAppId: "chromium-youtube.com__-Default"
    })
    eq(mockBar.saved.length, 3, "an invalid suggestion writes nothing")
    check(first.settingsError !== "", "invalid value reported")
    eq(first.retryable, false, "an invalid value is not offered for retry")
    first.saveMany({
      youtubeBrowser: "vivaldi"
    })
    eq(mockBar.saved.length, 3, "a removed setting can't be written")
    eq(first.preference("showArtist"), false, "saved value read back before the host reflects it")
    // Regression: a settings field follows a change made elsewhere (another
    // monitor, the bar editor) after being focused and left unchanged, and
    // leaving it again doesn't save the stale value back.
    var width = shell.findKey(view.settingsPage, "maxLabelWidth")
    check(width !== null, "label width field")
    if (width) {
      var before = mockBar.saved.length
      // tabbed through, unchanged
      width.commitEdit(true)
      first.settings = ({
          id: "foamy.media",
          hideWhenClosed: false,
          extra: "kept",
          maxLabelWidth: 320
        })
      eq(width.field.text, width.format(320), "field shows the external change")
      width.commitEdit(true)
      eq(mockBar.saved.length, before, "leaving it unchanged saves nothing")
      width.field.text = "250"
      width.dirty = true
      width.commitEdit(false)
      eq(mockBar.saved.length, before + 1, "a changed value commits once")
      eq(mockBar.saved[mockBar.saved.length - 1].settings.maxLabelWidth, 250, "saved value")
    }
    // No Browser or Profile rows: YouTube is focus-only.
    eq(shell.findKey(view.settingsPage, "youtubeBrowser"), null, "no browser field")
    eq(shell.findKey(view.settingsPage, "youtubeProfile"), null, "no profile field")
    check(shell.findKey(view.settingsPage, "youtubeAppId") !== null, "the app ID field stays")
    var mpris = shell.findKey(view.settingsPage, "youtubeMprisName")
    check(mpris !== null, "MPRIS name field")
    if (mpris) {
      mpris.field.text = "--evil"
      mpris.dirty = true
      mpris.commitEdit(false)
      check(mpris.error !== "", "an invalid MPRIS name is refused in the field")
      mpris.commitEdit(true)
      eq(mpris.field.text, mpris.value, "focus-out restores the saved name")
    }
    first.closeSettings()
    eq(view.blocked, false, "back from Settings")
    first.close()
    // Covers stay decoded for a moment after closing (Panel.imageRelease).
    wait.waitFor(function () {
      return !first.member.demanded && !first.imagesActive
    }, 10000, shell.stepThree, "closing releases demand and covers")
  }

  function stepThree() {
    var first = panels.itemAt(0)
    eq(first.editingSettings, false, "closing leaves Settings")
    // The grown label lays out again in its wider slot instead of keeping
    // the ellipsis of the shorter text.
    var growText = findNamed(growBar, "mediaBarLabel").children[0]
    check(growText.width >= growText.implicitWidth, "the slot fits a grown label: " + growText.width + " < " + growText.implicitWidth)
    eq(growText.truncated, false, "a grown label that fits is not elided")
    check(growText.contentWidth >= growText.implicitWidth - 1, "the grown label is drawn whole: " + growText.contentWidth)
    // The settings IPC on a closed popup lands on Settings (reset on close only).
    first.openSettings()
    eq(first.opened, true, "settings opens the popup")
    eq(first.editingSettings, true, "and lands on Settings")
    first.close()
    eq(first.editingSettings, false, "closing resets it")
    // A widget hidden by "Hide when stopped" opened through IPC: centred
    // under the bar, not in the screen corner.
    var hidden = hiddenPanel.createObject(barRow, {
      bar: mockBar,
      moduleName: "foamy.media",
      settings: ({
          id: "foamy.media"
        })
    })
    eq(hidden.shown, false, "nothing playing hides the widget")
    eq(hidden.popup.centerOnBar, true, "hidden widget centres its popup")
    hidden.open()
    wait.waitFor(function () {
      return hidden.popup.screenW > 0 && hidden.popup.bodyItem !== null
    }, 10000, function () {
      shell.stepFour(hidden)
    }, "the hidden widget's popup opens")
  }

  Component {
    id: hiddenPanel
    Media.Panel {}
  }
  function stepFour(hidden) {
    var popup = hidden.popup
    check(popup.screenW > 0, "popup knows its screen")
    check(Math.abs(popup.cardOrigin.x + popup.contentWidth / 2 - popup.screenW / 2) <= 1, "card centred on the screen: " + popup.cardOrigin.x)
    check(popup.cardOrigin.x > popup.margin && popup.cardOrigin.y > 0, "not in the top-left corner")
    eq(panels.itemAt(0).popup.centerOnBar, false, "a shown widget still hangs from itself")
    hidden.close()
    hidden.destroy()
    keySteps.begin()
  }

  // The keys after Settings hides, with real keys through the host's
  // KeyboardPanel: the popup closed on Settings and opened again closes on
  // Esc, and Esc on Settings goes back, then the next Esc closes the popup.
  QtObject {
    id: keySteps
    function focused() {
      var view = panels.itemAt(0).popup.bodyItem
      var window = view ? view.Window.window : null
      return window ? window.activeFocusItem : null
    }
    function inside(item, ancestor) {
      for (var at = item; at; at = at.parent)
        if (at === ancestor)
          return true
      return false
    }
    function esc() {
      ev.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
    }
    // Opens Settings, then runs `then` once its page has the keys.
    function showSettings(label, then) {
      var first = panels.itemAt(0)
      first.openSettings()
      wait.waitFor(function () {
        var view = first.popup.bodyItem
        return view !== null && view.settingsPage.visible && keySteps.inside(keySteps.focused(), view.settingsPage)
      }, 10000, then, label + ": the settings page has the keys")
    }
    // Opens the popup, then runs `then` once the host has given its body the keys.
    function reopen(label, then) {
      var first = panels.itemAt(0)
      first.open()
      wait.waitFor(function () {
        var view = first.popup.bodyItem
        return first.popup.open && view !== null && keySteps.inside(keySteps.focused(), view)
      }, 10000, then, label + ": the popup opens with the keys in its body")
    }
    function begin() {
      keySteps.showSettings("closed on Settings", function () {
        var first = panels.itemAt(0)
        first.close()
        eq(first.editingSettings, false, "closing the popup leaves Settings")
        keySteps.reopen("closed on Settings", function () {
          check(!keySteps.inside(keySteps.focused(), first.popup.bodyItem.settingsPage), "the hidden settings page has no keys after the open: " + keySteps.focused())
          keySteps.esc()
          eq(first.opened, false, "Esc closes the popup that was closed on Settings")
          keySteps.back()
        })
      })
    }
    function back() {
      keySteps.reopen("Back", function () {
        keySteps.showSettings("Back", function () {
          var first = panels.itemAt(0)
          keySteps.esc()
          check(!first.editingSettings && first.opened, "Esc on Settings goes back")
          wait.waitFor(function () {
            return !keySteps.inside(keySteps.focused(), first.popup.bodyItem.settingsPage)
          }, 3000, function () {
            keySteps.esc()
            eq(first.opened, false, "the next Esc closes the popup")
            // Closed for the steps after these, also when a check failed.
            first.close()
            focusSteps.begin()
          }, "the keys leave the hidden settings page after Back")
        })
      })
    }
  }

  // YouTube is focus-only (regression: with no YouTube window, launch()
  // started the browser as a child of this bar). A stand-in window list
  // gives the panel a YouTube web-app window to focus.
  QtObject {
    id: fakeYoutubeWindow
    property string appId: "vivaldi-youtube.com__-Default"
    property string title: "Example - YouTube"
    property bool activated: false
    property int activations: 0
    function activate() {
      activations++
    }
  }
  QtObject {
    id: focusSteps
    function begin() {
      var first = panels.itemAt(0)
      // The app ID the panel matches (a suggestion saved earlier set it).
      fakeYoutubeWindow.appId = first.preference("youtubeAppId")
      first.toplevelModel = {
        values: [fakeYoutubeWindow]
      }
      eq(first.youtubeOpen, true, "the YouTube window is matched by its app ID")
      first.selectSource("youtube")
      eq(first.sourceKind, "youtube", "YouTube selected")
      // The window is open but no player matches it: the hover text agrees
      // with the popup's "Nothing playing".
      eq(first.live, false, "no YouTube player")
      eq(first.tooltipText, FoamyI18n.t("Nothing playing"), "tooltip for an open source with no player")
      eq(first.launch(), true, "launch() acts on an open YouTube window")
      eq(fakeYoutubeWindow.activations, 1, "launch() focuses the YouTube window")
      eq(first.playPause(), false, "play/pause without a YouTube player is not a transport call")
      eq(fakeYoutubeWindow.activations, 2, "and focuses the window instead")
      // The window closes; until the leader moves the selection on, YouTube
      // stays selected with nothing to focus.
      first.toplevelModel = {
        values: []
      }
      eq(first.youtubeOpen, false, "the YouTube window is gone")
      eq(first.tooltipText, FoamyI18n.t("%1 is not running", "YouTube"), "tooltip once the window is gone")
      eq(first.sourceKind, "youtube", "still selected this frame")
      eq(first.launch(), false, "launch() without the YouTube window does nothing")
      eq(first.playPause(), false, "nor does play/pause")
      eq(fakeYoutubeWindow.activations, 2, "nothing is focused")
      eq(JSON.stringify(mockBar.ran), "[]", "YouTube launches run no command")
      eq(first.settingsError, "", "no error")
      eq(first.editingSettings, false, "no settings page")
      first.toplevelModel = ToplevelManager.toplevels
      Media.MediaService.selectedSource = "spotify"
      eq(first.launch(), true, "Spotify keeps Omarchy's launcher")
      eq(JSON.stringify(mockBar.ran), JSON.stringify(["omarchy launch spotify"]), "Spotify runs Omarchy's launcher, once")
      // The art probe's command not starting ends the attempt too.
      var svc = Media.MediaService
      var a = "file:///nonexistent/foamy-media-a.png", b = "file:///nonexistent/foamy-media-b.png"
      svc.request(a)
      svc.artProbeDelay.stop()
      svc.applyArtProbe(a, '{"ok":true,"mean":"#336699","file":"/tmp/a.png","swatches":[]}')
      svc.request(b)
      svc.artProbeDelay.stop()
      eq(svc.artSettling, true, "the next cover settles")
      svc.artProbe.pending = b
      svc.artProbe.exitSeen = false
      svc.artProbe.command = ["foamy-media-no-such-helper"]
      svc.artProbe.running = true
      wait.waitFor(function () {
        return !svc.artProbe.running && !svc.artSettling
      }, 10000, focusSteps.finish, "the art probe that can't start ends")
    }
    function finish() {
      var first = panels.itemAt(0)
      var svc = Media.MediaService
      eq(svc.artFile, "", "a probe that can't start keeps no previous cover")
      svc.request("")
      svc.artProbeDelay.stop()
      // A browser start would have failed or opened Settings by now.
      eq(first.settingsError, "", "still no error after the YouTube launch calls")
      eq(first.editingSettings, false, "and no settings page")
      eq(first.sourceKind, "spotify", "Spotify selected")
      eq(fakeYoutubeWindow.activations, 2, "the stand-in window was only focused while open")
      // The steps below do not depend on the language: tests/runtime.py
      // asks for them in one run only.
      if (Quickshell.env("FOAMY_HINT") === "1")
        controlSteps.begin()
      else
        shell.finish()
    }
  }

  TestEvent {
    id: ev
  }
  // A playing Spotify that records what the widget asks of it. Panel binds to
  // these properties, so they notify (a QtObject, not a plain object).
  Component {
    id: playerStandIn
    QtObject {
      property string dbusName: "org.mpris.MediaPlayer2.spotify"
      property string identity: "Spotify"
      property bool isPlaying: true
      property int playbackState: isPlaying ? MprisPlaybackState.Playing : MprisPlaybackState.Paused
      property string trackTitle: "T"
      property string trackArtist: "A"
      property bool lengthSupported: true
      property real length: 200
      property bool positionSupported: true
      property real position: 50
      property bool canSeek: true
      property bool canGoNext: true
      property bool canGoPrevious: true
      property bool volumeSupported: true
      property real volume: 0.5
      property bool loopSupported: true
      property int loopState: MprisLoopState.None
      property bool shuffleSupported: true
      property bool shuffle: false
      property int nexts: 0
      property int previouses: 0
      // The position tick re-reads by emitting positionChanged.
      property int ticks: 0
      onPositionChanged: ticks++
      function next() {
        nexts++
      }
      function previous() {
        previouses++
      }
    }
  }

  // Clicks, source selection, the tab equalizer, the position tick, the
  // wheel and the transport, on the real panels. Every step puts the real
  // player and window models back before the next.
  QtObject {
    id: controlSteps
    property var stand: null
    function begin() {
      var first = panels.itemAt(0)
      // The host bar's click entry point, with no player (left click opens
      // the popup by default).
      mockBar.ran = []
      first.triggerPress(Qt.LeftButton)
      wait.waitFor(function () {
        return first.opened
      }, 10000, function () {
        first.triggerPress(Qt.LeftButton)
        wait.waitFor(function () {
          return !first.opened
        }, 10000, controlSteps.clickPlays, "a second left click closes the popup")
      }, "a left click opens the popup")
    }
    function clickPlays() {
      var first = panels.itemAt(0)
      first.triggerPress(Qt.MiddleButton)
      eq(first.opened, false, "a middle click without a player opens nothing")
      eq(JSON.stringify(mockBar.ran), "[]", "and runs nothing")
      first.save("leftClick", "Play/pause")
      first.triggerPress(Qt.LeftButton)
      eq(JSON.stringify(mockBar.ran), JSON.stringify(["omarchy launch spotify"]), "left click set to play/pause starts Spotify when nothing plays")
      eq(first.opened, false, "and opens no popup")
      first.triggerPress(Qt.RightButton)
      wait.waitFor(function () {
        return first.opened
      }, 10000, function () {
        first.close()
        first.save("leftClick", "Open panel")
        eq(first.leftClick, "Open panel", "left click opens the popup again")
        mockBar.ran = []
        wait.waitFor(function () {
          return !first.opened
        }, 10000, controlSteps.sources, "the popup closes")
      }, "then right click opens the popup")
    }
    // The leader keeps the selection in step with the players. An earlier
    // step saved YouTube names on the first panel that the bar never
    // reflects; wait until they expired back to the defaults, so the
    // stand-ins below match whichever panel leads.
    function sources() {
      var lead = shell.leader()
      wait.waitFor(function () {
        return lead.preference("youtubeAppId") === "vivaldi-youtube.com__-Default" && lead.preference("youtubeMprisName") === "vivaldi"
      }, 15000, controlSteps.sourcesSettled, "the leader's YouTube names are the defaults")
    }
    function sourcesSettled() {
      var lead = shell.leader()
      var spotify = {
        dbusName: "org.mpris.MediaPlayer2.spotify",
        identity: "Spotify",
        isPlaying: true,
        trackTitle: "T",
        trackArtist: "A",
        canSeek: false,
        shuffleSupported: false,
        // The leader's position tick re-reads through this signal.
        positionChanged: function () {}
      }
      var youtube = {
        dbusName: "org.mpris.MediaPlayer2." + lead.preference("youtubeMprisName") + ".instance1",
        identity: "YouTube",
        metadata: {},
        isPlaying: true,
        trackTitle: "Example",
        canSeek: false,
        shuffleSupported: false,
        positionChanged: function () {}
      }
      fakeYoutubeWindow.appId = lead.preference("youtubeAppId")
      fakeYoutubeWindow.title = "Example - YouTube"
      Media.MediaService.selectedSource = "youtube"
      lead.toplevelModel = {
        values: []
      }
      lead.playerModel = {
        values: [spotify]
      }
      wait.waitFor(function () {
        return Media.MediaService.selectedSource === "spotify"
      }, 10000, function () {
        lead.toplevelModel = {
          values: [fakeYoutubeWindow]
        }
        lead.playerModel = {
          values: [spotify, youtube]
        }
        wait.waitFor(function () {
          return Media.MediaService.selectedSource === "youtube"
        }, 10000, controlSteps.youtubeOff, "the source that starts playing last is selected")
      }, "a playing Spotify is selected")
    }
    function youtubeOff() {
      var lead = shell.leader()
      lead.saveMany({
        youtubeEnabled: false
      })
      eq(lead.youtubeOpen, false, "with YouTube off its window is not matched")
      wait.waitFor(function () {
        return Media.MediaService.selectedSource === "spotify"
      }, 10000, function () {
        lead.saveMany({
          youtubeEnabled: true
        })
        wait.waitFor(function () {
          return Media.MediaService.selectedSource === "youtube"
        }, 10000, function () {
          lead.toplevelModel = {
            values: []
          }
          wait.waitFor(function () {
            return Media.MediaService.selectedSource === "spotify"
          }, 10000, function () {
            lead.playerModel = Mpris.players
            lead.toplevelModel = ToplevelManager.toplevels
            controlSteps.tabEqualizer()
          }, "the YouTube window closed: back to Spotify")
        }, "YouTube on again: it is selected")
      }, "with YouTube off, Spotify is selected")
    }
    // The popup's Spotify tab animates its equalizer only while the popup
    // is open and Settings is not.
    function tabEqualizer() {
      var tab = null
      function findTab(item) {
        if (!item || tab)
          return
        if (item.key === "tab:spotify" && item.kind !== undefined)
          tab = item
        for (var i = 0; i < (item.children || []).length; i++)
          findTab(item.children[i])
      }
      findTab(playerView)
      var equalizerItem = null
      function findEqualizer(item) {
        if (!item || equalizerItem)
          return
        if (item.stepping !== undefined)
          equalizerItem = item
        for (var i = 0; i < (item.children || []).length; i++)
          findEqualizer(item.children[i])
      }
      findEqualizer(tab)
      check(equalizerItem !== null, "the Spotify tab has an equalizer")
      if (equalizerItem) {
        eq(equalizerItem.stepping, !FoamyMotion.reduceMotion, "the tab's equalizer steps while the popup is open")
        player.editingSettings = true
        eq(equalizerItem.stepping, false, "and rests while Settings is open")
        player.editingSettings = false
        player.opened = false
        eq(equalizerItem.stepping, false, "and while the popup is closed")
        player.opened = true
      }
      controlSteps.positionTick()
    }
    // The position is re-read while playing, and only while a popup is open
    // or the underline shows. Every bar sees the same player, so only the
    // leader re-reads it: the other bars get playing stand-ins of their own
    // that must never tick. The 500 ms rate of an open popup is not checked,
    // because a rate check would fail under load.
    property var others: []
    function positionTick() {
      var lead = shell.leader()
      stand = playerStandIn.createObject(shell)
      others = []
      for (var i = 0; i < 3; i++) {
        var panel = panels.itemAt(i)
        var own = panel === lead ? stand : playerStandIn.createObject(shell)
        if (panel !== lead)
          others = others.concat([own])
        panel.playerModel = {
          values: [own]
        }
      }
      Media.MediaService.selectedSource = "spotify"
      for (var p = 0; p < 3; p++)
        eq(panels.itemAt(p).playing, true, "bar " + p + " plays its stand-in")
      // With the underline off and every popup closed, nothing asks for the
      // position. An absence check, like the paused one below. A 1 s track
      // gets the shortest underline interval (1 s), so a tick that ignores
      // the setting falls inside the window.
      lead.save("showProgress", false)
      stand.length = 1
      eq(lead.showProgress, false, "the underline is off")
      wait.after(1200, function () {
        eq(stand.ticks, 0, "no position reads with the underline off and the popup closed")
        stand.length = 200
        lead.open()
        wait.waitFor(function () {
          return stand.ticks >= 2
        }, 5000, controlSteps.pausedTick, "the open popup re-reads the position")
      })
    }
    function pausedTick() {
      var lead = shell.leader()
      stand.isPlaying = false
      var ticks = stand.ticks
      // An absence check: nothing may re-read a paused player. The other
      // bars still play while the popup is open.
      wait.after(1200, function () {
        eq(stand.ticks, ticks, "no position reads while paused")
        for (var i = 0; i < others.length; i++)
          eq(others[i].ticks, 0, "bar that does not lead, stand-in " + i + ": no position reads")
        lead.close()
        lead.save("showProgress", true)
        stand.isPlaying = true
        wait.waitFor(function () {
          return !lead.opened
        }, 10000, controlSteps.wheel, "the leader's popup closes")
      })
    }
    // Discrete mouse-wheel notches over the widget.
    function wheel() {
      var lead = shell.leader()
      var x = lead.width / 2, y = lead.height / 2
      // First with the wheel off, before a skip starts the skip cooldown.
      lead.save("scrollAction", "Nothing")
      ev.mouseWheel(lead, x, y, Qt.NoButton, Qt.NoModifier, 0, 120, -1)
      ev.mouseWheel(lead, x, y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
      eq(stand.volume, 0.5, "with the wheel off, notches leave the volume")
      eq(stand.nexts, 0, "with the wheel off, notches skip nothing forward")
      eq(stand.previouses, 0, "with the wheel off, notches skip nothing back")
      lead.save("scrollAction", "Previous/next track")
      ev.mouseWheel(lead, x, y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
      eq(stand.nexts, 1, "one notch down skips to the next track")
      ev.mouseWheel(lead, x, y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
      eq(stand.nexts, 1, "a second notch within the cooldown skips nothing")
      lead.save("scrollAction", "Volume")
      ev.mouseWheel(lead, x, y, Qt.NoButton, Qt.NoModifier, 0, 120, -1)
      check(Math.abs(stand.volume - 0.55) < 1e-6, "with the wheel on volume, one notch up adds the 5 % step: " + stand.volume)
      eq(stand.previouses, 0, "and skips nothing")
      lead.save("scrollAction", "Previous/next track")
      controlSteps.transport()
    }
    // The transport calls bound what they write to the player.
    function transport() {
      var lead = shell.leader()
      eq(lead.seekTo(-5), true, "a seek is accepted")
      eq(stand.position, 0, "a seek before the start lands on 0")
      lead.seekTo(9999)
      eq(stand.position, 200, "a seek past the end lands on the length")
      lead.setVolume(2)
      eq(stand.volume, 1, "volume is capped at 100 %")
      lead.setVolume(-1)
      eq(stand.volume, 0, "and never below 0")
      var loops = []
      for (var n = 0; n < 3; n++) {
        lead.cycleLoop()
        loops.push(stand.loopState)
      }
      eq(JSON.stringify(loops), JSON.stringify([MprisLoopState.Playlist, MprisLoopState.Track, MprisLoopState.None]), "repeat cycles playlist, track, off")
      eq(lead.toggleShuffle(), true, "shuffle is toggled")
      eq(stand.shuffle, true, "shuffle on")
      stand.canSeek = false
      eq(lead.seekTo(10), false, "a player that can't seek refuses the seek")
      eq(stand.position, 200, "and its position is unchanged")
      for (var i = 0; i < 3; i++)
        panels.itemAt(i).playerModel = Mpris.players
      stand.destroy()
      stand = null
      for (var o = 0; o < others.length; o++)
        others[o].destroy()
      others = []
      hintSteps.begin()
    }
  }

  // Omarchy's YouTube app hint. tests/runtime.py puts a fake
  // omarchy-webapp-window-class first on PATH that answers, in turn: the
  // Chromium class, a failure, a hang, two lines, 1 MB of junk, the class.
  QtObject {
    id: hintSteps
    property var panel: null
    property var hintPicker: null
    property int asked: 0
    property double started: 0
    readonly property string omarchyId: "chrome-youtube.com__-Default"
    readonly property var chromeWindow: ({
        appId: "chrome-youtube.com__-Default",
        title: "Omarchy - YouTube"
      })
    readonly property var vivaldiWindow: ({
        appId: "vivaldi-youtube.com__-Default",
        title: "Vivaldi - YouTube"
      })
    function begin() {
      var svc = Media.MediaService
      eq(svc.youtubeAppIdHintAnswers, 0, "nothing asks Omarchy before a picker opens")
      panel = hiddenPanel.createObject(barRow, {
        bar: mockBar,
        moduleName: "foamy.media",
        settings: ({
            id: "foamy.media",
            hideWhenClosed: false
          })
      })
      panel.toplevelModel = {
        values: [chromeWindow]
      }
      panel.playerModel = {
        values: [
          {
            dbusName: "org.mpris.MediaPlayer2.chromium.instance7",
            identity: "Chromium"
          }
        ]
      }
      eq(panel.preference("youtubeAppId"), "vivaldi-youtube.com__-Default", "the default app ID is still Vivaldi's")
      eq(panel.preference("youtubeMprisName"), "vivaldi", "and so is the MPRIS name")
      panel.openSettings()
      panel.browserSettingsOpen = true
      wait.waitFor(function () {
        return shell.findNamed(panel.popup.bodyItem, "browserPickerHeader") !== null
      }, 10000, function () {
        var header = shell.findNamed(panel.popup.bodyItem, "browserPickerHeader")
        hintSteps.hintPicker = header ? header.parent : null
        check(hintSteps.hintPicker !== null, "the settings page has the window picker")
        eq(svc.youtubeAppIdHintAnswers, 0, "opening Settings asks nothing")
        hintSteps.ask(hintSteps.afterClass)
      }, "the hint panel's settings page")
    }
    // Close and open the picker: each opening asks once.
    function ask(then) {
      if (!hintSteps.hintPicker) {
        shell.finish()
        return
      }
      hintSteps.hintPicker.expanded = false
      asked++
      started = Date.now()
      hintSteps.hintPicker.expanded = true
      var target = asked
      wait.waitFor(function () {
        return Media.MediaService.youtubeAppIdHintAnswers === target
      }, 15000, then, "answer " + target + " to the window-class question")
    }
    function rows() {
      return panel.browserCandidates.map(function (row) {
        return row.id + (row.hinted ? " (hinted)" : "")
      }).join(", ")
    }
    function noHint(label) {
      eq(Media.MediaService.omarchyYoutubeAppId, "", label + ": no Omarchy class")
      eq(panel.youtubeAppIdHint, "", label + ": no hint")
      eq(rows(), omarchyId, label + ": the window is listed, unmarked")
    }
    function afterClass() {
      eq(Media.MediaService.omarchyYoutubeAppId, omarchyId, "Omarchy's class is read")
      eq(panel.youtubeAppIdHint, omarchyId, "the hint applies to an unset app ID")
      eq(rows(), omarchyId + " (hinted)", "Omarchy's window is the marked row")
      var first = panel.browserCandidates[0]
      eq(JSON.stringify(first ? first.values : null), JSON.stringify({
        youtubeAppId: omarchyId,
        youtubeMprisName: "chromium"
      }), "one click sets its app ID and player")
      var note = shell.findNamed(hintSteps.hintPicker, "browserHintNote")
      check(note !== null && note.visible, "the row says it is Omarchy's YouTube app")
      if (note)
        eq(note.text, FoamyI18n.t("Omarchy's YouTube app"), "the hint note's text")
      ask(afterFailure)
    }
    function afterFailure() {
      noHint("the command fails")
      check(shell.findNamed(hintSteps.hintPicker, "browserHintNote") === null || !shell.findNamed(hintSteps.hintPicker, "browserHintNote").visible, "no hint note")
      ask(afterHang)
    }
    function afterHang() {
      noHint("the command hangs")
      check(Date.now() - started < 8000, "a hanging command is ended within its deadline: " + (Date.now() - started) + " ms")
      ask(afterTwoLines)
    }
    function afterTwoLines() {
      noHint("the command prints two lines")
      ask(afterFlood)
    }
    function afterFlood() {
      noHint("the command prints 1 MB")
      ask(afterAgain)
    }
    function afterAgain() {
      eq(panel.youtubeAppIdHint, omarchyId, "the hint is back")
      // A Vivaldi window matching the default app ID: that setup is left alone.
      panel.toplevelModel = {
        values: [chromeWindow, vivaldiWindow]
      }
      eq(panel.youtubeAppIdHint, "", "no hint while the default app ID's window is open")
      eq(rows(), omarchyId + ", vivaldi-youtube.com__-Default", "rows by title, none marked")
      panel.toplevelModel = {
        values: [chromeWindow]
      }
      eq(panel.youtubeAppIdHint, omarchyId, "hint again without it")
      // An app ID the user set: no hint.
      panel.saveMany({
        youtubeAppId: "vivaldi-youtube.com__-Profile_1"
      })
      eq(panel.youtubeAppIdHint, "", "no hint once an app ID is set")
      eq(rows(), omarchyId, "and no marked row")
      eq(Media.MediaService.youtubeAppIdHintAnswers, asked, "one answer per opening, none from a poll")
      panel.close()
      panel.destroy()
      // tests/runtime.py's IPC checks expect no player on the leader.
      eq(shell.leader().live, false, "stand-ins removed before the IPC checks")
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
    onTriggered: {
      console.log("FOAMY DONE")
      Qt.quit()
    }
  }
}
