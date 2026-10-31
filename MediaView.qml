pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "Model.js" as Model

// The popup body: the hero band (the cover as its picture, the track in its
// hero slot), seek, transport, volume, source tabs and the settings page.
// Everything comes from `media` (the Panel, or the preview's mock), so this
// file never touches MPRIS or a process.
//
// Keyboard (one cursor, hover moves it too): Up/Down (j/k) move between
// rows, Left/Right (h/l) move along the transport and source rows and seek
// or change the volume on the slider rows, Enter/Space activate (play/pause
// when nothing has the cursor), s opens Settings, Tab/Shift-Tab switch bar
// panels, Esc closes (or leaves Settings).
PanelKeyCatcher {
  id: view

  required property var media

  readonly property bool editing: media.editingSettings === true
  readonly property bool compact: media.compactPanel === true
  // MultiEffect draws nothing under the software renderer (Omarchy CPU
  // rendering); the panel then keeps its plain surface and square cover.
  readonly property bool effectsAvailable: GraphicsInfo.api !== GraphicsInfo.Software
  // Source brand glyphs come from the bar's (nerd) font, as in the bar.
  readonly property string glyphFamily: media.bar && media.bar.fontFamily ? media.bar.fontFamily : FoamyStyle.monoFamily
  // The cover as the band's picture (Settings → Artwork background).
  readonly property bool pictureShown: media.artBackground === true && media.artSource !== ""
  readonly property bool backdropShown: pictureShown && effectsAvailable

  implicitWidth: FoamyStyle.popupWidth
  implicitHeight: editing ? settingsPage.implicitHeight : main.implicitHeight
  blocked: editing

  function resetView() {
    cursor.reset()
    mainScroll.contentY = 0
  }
  // The row holding a cursor stop, to scroll it into view.
  function rowItem(key) {
    if (key === "settings") return band
    if (key === "seek") return seekRow
    if (key === "volume") return volumeRow
    if (key.indexOf("tab:") === 0 || key === "launch") return footer
    return key !== "" ? transport : null
  }
  function keepVisible(item) {
    if (!item || !item.visible) return
    var point = item.mapToItem(main, 0, 0)
    if (point.y < mainScroll.contentY) mainScroll.contentY = Math.max(0, point.y)
    else if (point.y + item.height > mainScroll.contentY + mainScroll.height)
      mainScroll.contentY = Math.max(0, Math.min(mainScroll.contentHeight - mainScroll.height, point.y + item.height - mainScroll.height))
  }
  onCursorKeyChanged: keepVisible(rowItem(cursorKey))
  Component.onCompleted: resetView()
  Connections {
    target: view.media
    ignoreUnknownSignals: true
    function onOpenedChanged() { if (view.media.opened) view.resetView() }
    function onEditingSettingsChanged() {
      if (view.editing) Qt.callLater(function() { settingsPage.resetScroll(); settingsPage.focusBack() })
      else view.forceActiveFocus()
    }
  }

  // ---- Cursor ------------------------------------------------------------
  // Rows of stops, top to bottom; the cursor is an index into the flat list.
  readonly property bool seekShown: media.live === true && media.trackLength > 0
  readonly property bool spotifyTabShown: media.spotifyOpen === true || media.anySourceOpen !== true
  readonly property var rows: {
    var list = [["settings"]]
    if (seekShown) list.push(["seek"])
    if (media.live) list.push(["shuffle", "previous", "playPause", "next", "loop"])
    if (media.volumeSupported) list.push(["volume"])
    var footer = []
    if (spotifyTabShown) footer.push("tab:spotify")
    if (media.youtubeOpen) footer.push("tab:youtube")
    footer.push("launch")
    list.push(footer)
    return list
  }
  readonly property var stops: [].concat.apply([], rows)
  readonly property string cursorKey: cursor.index >= 0 && cursor.index < stops.length ? stops[cursor.index] : ""

  FoamyCursor { id: cursor; count: view.stops.length }

  function hasCursor(key) { return cursorKey === key }
  function hover(key) { var index = stops.indexOf(key); if (index >= 0) cursor.hover(index) }
  function place(key) { var index = stops.indexOf(key); if (index >= 0) cursor.index = index }
  function rowOf(key) {
    for (var i = 0; i < rows.length; i++) if (rows[i].indexOf(key) >= 0) return i
    return -1
  }
  function moveRow(dy) {
    var row = rowOf(cursorKey)
    var target = Math.max(0, Math.min(rows.length - 1, row + dy))
    if (target === row) return
    var from = rows[row], to = rows[target]
    // Into the transport row, land on play/pause; otherwise keep the column.
    var column = to.indexOf("playPause") >= 0 && from.length === 1 ? to.indexOf("playPause")
      : Math.min(to.length - 1, Math.max(0, from.indexOf(cursorKey)))
    place(to[column])
  }
  function moveAlong(dx) {
    var key = cursorKey
    // The timeline, transport and volume keep their physical direction in
    // RTL (see below), while PanelKeyCatcher reports reading order there.
    var physical = view.LayoutMirroring.enabled ? -dx : dx
    if (key === "seek") { media.seekBy(physical * 5); return }
    if (key === "volume") { media.setVolume(media.volume + physical * 0.05); return }
    var row = rows[rowOf(key)]
    var step = row.indexOf("playPause") >= 0 ? physical : dx
    var next = Math.max(0, Math.min(row.length - 1, row.indexOf(key) + step))
    place(row[next])
  }
  function activateStop() {
    var key = cursorKey
    if (key === "settings") media.openSettings()
    else if (key === "shuffle") media.toggleShuffle()
    else if (key === "previous") media.skipPrevious()
    else if (key === "next") media.skipNext()
    else if (key === "loop") media.cycleLoop()
    else if (key === "tab:spotify") media.selectSource("spotify")
    else if (key === "tab:youtube") media.selectSource("youtube")
    else if (key === "launch") { media.launch(); media.close() }
    else media.playPause()
  }

  onMoveRequested: function(dx, dy) {
    if (!cursor.active) { place(stops.indexOf("playPause") >= 0 ? "playPause" : stops[0]); return }
    if (dy !== 0) moveRow(dy)
    else if (dx !== 0) moveAlong(dx)
  }
  onActivateRequested: activateStop()
  onCloseRequested: media.close()
  onTabRequested: function(direction) { media.switchPanel(direction) }
  onTextKey: function(text, modifiers) {
    if (!cursor.plain(modifiers)) return
    if (String(text).toLowerCase() === "s") media.openSettings()
  }

  // ---- Main view ---------------------------------------------------------
  // The popup is capped by the screen (short screens, large UI scale); the
  // player then scrolls, and the cursor row is kept in view.
  Flickable {
    id: mainScroll
    objectName: "mediaMainScroll"
    visible: !view.editing
    anchors.fill: parent
    contentWidth: width
    contentHeight: main.implicitHeight
    clip: true
    interactive: contentHeight > height + 1
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
    onHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

    Column {
      id: main
      width: mainScroll.width

      // The hero band: the cover is the band's picture (blurred on the GPU
      // renderer, cover-fitted under the kit scrim otherwise), the title row
      // names the source and its state, the hero slot holds the cover and the
      // track. Without a cover (or with the artwork background off) the band
      // keeps the foamy wash.
      FoamyHeroBand {
        id: band
        width: parent.width
        iconName: "music"
        title: view.media.sourceName
        meta: !view.media.sourceOpen && !view.media.live ? FoamyI18n.t("Not running")
          : !view.media.live ? FoamyI18n.t("Nothing playing")
          : FoamyI18n.t(view.media.playing ? "Playing" : "Paused")
        settingsHasCursor: view.hasCursor("settings")
        onSettingsClicked: view.media.openSettings()
        onSettingsHovered: function(hovered) { if (hovered) view.hover("settings") }
        imageSource: view.pictureShown && !view.effectsAvailable ? view.media.artSource : ""
        background: view.backdropShown ? blurredCover : null
        // The blurred cover brings its own scrim, measured against the cover.
        scrim: !view.backdropShown && view.pictureShown

        RowLayout {
          id: coverRow
          Layout.fillWidth: true
          spacing: FoamyStyle.padding

          Rectangle {
            id: cover
            Layout.preferredWidth: Style.space(view.compact ? 72 : 96)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            radius: FoamyStyle.radius
            color: FoamyPalette.fieldFill
            layer.enabled: view.effectsAvailable && coverImage.status === Image.Ready
            layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask }

            Image {
              id: coverImage
              anchors.fill: parent
              // Decode only the physical pixels the thumbnail paints.
              sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
              sourceSize.height: Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              source: view.media.artSource
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              visible: coverImage.status !== Image.Ready
              text: view.media.sourceIcon
              textFormat: Text.PlainText
              color: view.media.sourceBrandColor
              font.family: view.glyphFamily
              font.pixelSize: FoamyStyle.font.displayLarge
            }
            Item {
              id: coverMask
              anchors.fill: parent
              visible: false
              layer.enabled: view.effectsAvailable
              Rectangle { anchors.fill: parent; radius: cover.radius; color: "white" }  // mask alpha source, never drawn
            }
          }

          ColumnLayout {
            id: metadata
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: FoamyStyle.gapTiny
            Text {
              Layout.fillWidth: true
              text: view.media.live ? (view.media.trackTitle || FoamyI18n.t("Nothing playing"))
                : view.media.sourceOpen ? FoamyI18n.t("Nothing playing") : FoamyI18n.t("%1 is not running", view.media.sourceName)
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: FoamyPalette.text
              font.family: FoamyStyle.fontFamily
              font.pixelSize: view.compact ? FoamyStyle.font.title : FoamyStyle.font.heading
              font.weight: Font.DemiBold
            }
            Text {
              visible: text !== ""
              Layout.fillWidth: true
              text: view.media.trackArtist
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              elide: Text.ElideRight
              color: FoamyPalette.text
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.body
            }
            Text {
              visible: text !== ""
              Layout.fillWidth: true
              text: view.media.trackAlbum
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              elide: Text.ElideRight
              color: FoamyPalette.secondaryText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.bodySmall
            }
          }
        }
      }

      Item { width: 1; height: FoamyStyle.gap }

      Column {
        id: controls
        x: FoamyStyle.gapLarge
        width: parent.width - FoamyStyle.gapLarge * 2
        spacing: FoamyStyle.gapSmall

        // Playback time, transport and volume keep their physical direction in RTL.
        FoamyCursorSurface {
          id: seekRow
          visible: view.seekShown
          width: parent.width
          height: seekColumn.implicitHeight + FoamyStyle.gap * 2
          foreground: FoamyPalette.text
          hasCursor: view.hasCursor("seek")
          onHovered: view.hover("seek")
          LayoutMirroring.enabled: false
          LayoutMirroring.childrenInherit: true
          Accessible.role: Accessible.Slider
          Accessible.name: FoamyI18n.t("Position")
          Column {
            id: seekColumn
            x: FoamyStyle.gap
            y: FoamyStyle.gap
            width: parent.width - FoamyStyle.gap * 2
            spacing: FoamyStyle.gapTiny
            PanelSlider {
              id: seekSlider
              width: parent.width
              bar: view.media.bar
              minimum: 0
              maximum: Math.max(1, view.media.trackLength)
              value: view.media.trackPosition
              step: 5
              trackColor: FoamyPalette.fieldFill
              fillColor: Commons.Color.accent
              knobColor: Commons.Color.accent
              knobSize: Style.space(10)
              enabled: view.media.canSeek === true
              opacity: enabled ? 1 : FoamyStyle.disabledOpacity
              onReleased: function(value) { view.media.seekTo(value) }
            }
            Item {
              width: parent.width
              height: elapsed.implicitHeight
              Text {
                id: elapsed
                anchors.left: parent.left
                text: Model.formatTime(seekSlider.dragging ? seekSlider.liveValue : view.media.trackPosition)
                textFormat: Text.PlainText
                color: FoamyPalette.secondaryText
                font.family: FoamyStyle.monoFamily
                font.pixelSize: FoamyStyle.font.bodySmall
              }
              Text {
                anchors.right: parent.right
                text: Model.formatTime(view.media.trackLength)
                textFormat: Text.PlainText
                color: FoamyPalette.secondaryText
                font.family: FoamyStyle.monoFamily
                font.pixelSize: FoamyStyle.font.bodySmall
              }
            }
          }
        }

        Row {
          id: transport
          visible: view.media.live === true
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Math.max(FoamyStyle.gap, (controls.width - Style.space(216)) / 4)
          LayoutMirroring.enabled: false
          LayoutMirroring.childrenInherit: true
          MediaControl {
            key: "shuffle"
            iconName: "shuffle"
            toggledOn: view.media.shuffleOn === true
            tooltipText: FoamyI18n.t(view.media.shuffleOn ? "Shuffle on" : "Shuffle off")
            enabled: view.media.shuffleSupported === true
            onClicked: view.media.toggleShuffle()
          }
          MediaControl {
            key: "previous"
            iconName: "skip-back"
            tooltipText: FoamyI18n.t("Previous track")
            enabled: view.media.canGoPrevious === true
            onClicked: view.media.skipPrevious()
          }
          MediaControl {
            key: "playPause"
            width: Style.space(48)
            height: width
            radius: FoamyStyle.pillRadius(width)
            iconName: view.media.playing ? "pause" : "play"
            iconSize: FoamyStyle.headerIconSize
            foreground: Commons.Color.popups.background
            color: hasCursor || hovered ? Commons.Color.accent : FoamyPalette.text
            tooltipText: FoamyI18n.t(view.media.playing ? "Pause" : "Play")
            enabled: view.media.live === true
            onClicked: view.media.playPause()
          }
          MediaControl {
            key: "next"
            iconName: "skip-forward"
            tooltipText: FoamyI18n.t("Next track")
            enabled: view.media.canGoNext === true
            onClicked: view.media.skipNext()
          }
          MediaControl {
            key: "loop"
            iconName: view.media.loopName === "track" ? "repeat-1" : "repeat"
            toggledOn: view.media.loopName !== "off"
            tooltipText: FoamyI18n.t(view.media.loopName === "track" ? "Repeat: track"
              : view.media.loopName === "playlist" ? "Repeat: playlist" : "Repeat: off")
            enabled: view.media.loopSupported === true
            onClicked: view.media.cycleLoop()
          }
        }

        FoamyCursorSurface {
          id: volumeRow
          visible: view.media.volumeSupported === true
          width: parent.width
          height: FoamyStyle.rowHeight
          foreground: FoamyPalette.text
          hasCursor: view.hasCursor("volume")
          onHovered: view.hover("volume")
          LayoutMirroring.enabled: false
          LayoutMirroring.childrenInherit: true
          Accessible.role: Accessible.Slider
          Accessible.name: FoamyI18n.t("Volume")
          FoamyIcon {
            id: volumeIcon
            anchors.left: parent.left
            anchors.leftMargin: FoamyStyle.gap
            anchors.verticalCenter: parent.verticalCenter
            width: FoamyStyle.iconSize
            height: width
            name: view.media.volume < 0.01 ? "volume-x" : "volume-2"
            color: FoamyPalette.secondaryText
          }
          PanelSlider {
            id: volumeSlider
            anchors.left: volumeIcon.right
            anchors.right: volumeText.left
            anchors.leftMargin: FoamyStyle.gapLarge
            anchors.rightMargin: FoamyStyle.gapLarge
            anchors.verticalCenter: parent.verticalCenter
            bar: view.media.bar
            minimum: 0
            maximum: 1
            step: 0.05
            value: view.media.volume
            trackColor: FoamyPalette.fieldFill
            fillColor: Commons.Color.accent
            knobColor: Commons.Color.accent
            knobSize: Style.space(10)
            onMoved: function(value) { view.media.setVolume(value) }
          }
          Text {
            id: volumeText
            anchors.right: parent.right
            anchors.rightMargin: FoamyStyle.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            text: FoamyI18n.t("%1%", FoamyI18n.number(Math.round(volumeSlider.liveValue * 100)))
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.monoFamily
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
      }

      Item {
        id: footer
        width: parent.width
        height: FoamyStyle.controlHeight + FoamyStyle.gapLarge * 2
        Rectangle {
          // Not under the band's own hairline when there are no controls.
          visible: view.seekShown || view.media.live === true || view.media.volumeSupported === true
          x: FoamyStyle.padding
          y: FoamyStyle.gap
          width: parent.width - FoamyStyle.padding * 2
          height: 1
          color: FoamyPalette.divider
        }
        Row {
          anchors.left: parent.left
          anchors.leftMargin: FoamyStyle.gapLarge
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: FoamyStyle.gapTiny
          spacing: FoamyStyle.gapSmall
          SourceTab {
            kind: "spotify"
            visible: view.spotifyTabShown
            enabled: view.media.spotifyOpen === true
            label: "Spotify"
            iconText: "\u{f1bc}"
            accent: view.media.spotifyGreen
            playing: view.media.spotifyPlaying === true
          }
          SourceTab {
            kind: "youtube"
            visible: view.media.youtubeOpen === true
            label: "YouTube"
            iconText: "\u{f16a}"
            accent: view.media.youtubeRed
            playing: view.media.youtubePlaying === true
          }
        }
        FoamyAction {
          anchors.right: parent.right
          anchors.rightMargin: FoamyStyle.gapLarge
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: FoamyStyle.gapTiny
          iconName: "external-link"
          foreground: FoamyPalette.secondaryText
          hasCursor: view.hasCursor("launch")
          tooltipText: FoamyI18n.t(view.media.sourceOpen ? "Show %1" : "Start %1", view.media.sourceName)
          onHoveredChanged: if (hovered) view.hover("launch")
          onClicked: { view.media.launch(); view.media.close() }
        }
      }
    }
  }

  // ---- Settings ----------------------------------------------------------
  readonly property alias settingsPage: settingsPage
  readonly property alias band: band
  MediaSettings {
    id: settingsPage
    visible: view.editing
    width: parent.width
    height: parent.height
    media: view.media
  }

  // ---- Blurred cover (GPU renderer) ---------------------------------------
  // The measured cover as the band's picture: blurred hard, desaturated a
  // little and dimmed by its brightness, under a scrim of the theme surface
  // tinted towards the cover at the opacity the cover's brightness calls for
  // (artIntensity). It keeps to the band's rounded top itself.
  Component {
    id: blurredCover
    Item {
      id: backdrop
      // Blurring samples past the edges of its source, so the cover is drawn
      // larger than the band and the mask cuts it back, which puts the fade
      // safely outside. The blur's own padding is drawn beyond the mask on
      // the GPU renderer, so the band's rectangle clips it too: the picture
      // never reaches the progress row below the band.
      clip: true
      readonly property real bleed: Style.space(32)
      readonly property real corner: band.topRadius
      readonly property real scrimStrength: Model.scrimAlpha(view.media.artLuma, view.media.artIntensity)
      readonly property color scrimColor: {
        var base = Commons.Color.popups.background
        if (view.media.artDominant === "") return Qt.rgba(base.r, base.g, base.b, scrimStrength)
        var dominant = Qt.color(view.media.artDominant)
        var mixed = Qt.tint(base, Qt.rgba(dominant.r, dominant.g, dominant.b, 0.20))
        return Qt.rgba(mixed.r, mixed.g, mixed.b, scrimStrength)
      }
      Image {
        id: artBlurSource
        anchors.fill: parent
        anchors.margins: -backdrop.bleed
        source: view.media.artSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        // A fixed decode size: the blur erases anything finer, and binding
        // it to the item would re-decode whenever the popup resizes.
        sourceSize.width: 384
        sourceSize.height: 384
      }
      MultiEffect {
        anchors.fill: artBlurSource
        source: artBlurSource
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        blurMultiplier: 1.6
        saturation: 0.2
        // Bright patches, not the average, swallow a caption.
        contrast: -0.1
        brightness: Model.artBrightness(view.media.artLuma)
        maskEnabled: true
        maskSource: cornerMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.05
        // A track change cross-fades instead of flashing the theme.
        opacity: artBlurSource.status === Image.Ready ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: FoamyMotion.slow; easing.type: Easing.OutCubic } }
      }
      // The band-sized rectangle inside the bleed is the only part that
      // survives; its lower corners meet the body and stay square.
      Item {
        id: cornerMask
        anchors.fill: artBlurSource
        layer.enabled: true
        visible: false
        Rectangle {
          anchors.fill: parent
          anchors.margins: backdrop.bleed
          radius: backdrop.corner
          bottomLeftRadius: 0
          bottomRightRadius: 0
          color: "black" // mask alpha source, never drawn
        }
      }
      Rectangle {
        anchors.fill: parent
        radius: backdrop.corner
        bottomLeftRadius: 0
        bottomRightRadius: 0
        color: backdrop.scrimColor
        Behavior on color { ColorAnimation { duration: FoamyMotion.slow; easing.type: Easing.OutCubic } }
      }
    }
  }

  // ---- Building blocks ---------------------------------------------------
  // Transport buttons: kit icons on the foamy action surface, a little larger
  // than a header action. Mode state (shuffle, repeat) stays filled whatever
  // has the cursor.
  component MediaControl: FoamyAction {
    id: control
    property string key: ""
    property bool toggledOn: false
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: Style.space(36)
    height: Style.space(36)
    iconSize: FoamyStyle.iconSize + Style.space(3)
    hasCursor: view.hasCursor(key)
    foreground: toggledOn && enabled ? Commons.Color.popups.background : FoamyPalette.secondaryText
    color: toggledOn && enabled ? Commons.Color.accent
      : (hasCursor || hovered) && enabled ? FoamyPalette.hoverFill : "transparent"
    onHoveredChanged: if (hovered) view.hover(control.key)
  }

  component SourceTab: FoamyCursorSurface {
    id: tab
    required property string kind
    required property string label
    required property string iconText
    required property color accent
    required property bool playing
    readonly property bool selected: view.media.sourceKind === kind
    readonly property string key: "tab:" + kind

    implicitWidth: tabContent.implicitWidth + FoamyStyle.gap * 2
    implicitHeight: FoamyStyle.actionSize
    foreground: FoamyPalette.text
    hasCursor: view.hasCursor(key)
    onHovered: view.hover(key)
    onClicked: if (tab.enabled) view.media.selectSource(tab.kind)
    Accessible.role: Accessible.PageTab
    Accessible.name: label
    Accessible.selected: selected

    Row {
      id: tabContent
      anchors.centerIn: parent
      spacing: FoamyStyle.gapSmall
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tab.iconText
        textFormat: Text.PlainText
        color: tab.accent
        font.family: view.glyphFamily
        font.pixelSize: FoamyStyle.font.title
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tab.label
        textFormat: Text.PlainText
        color: tab.selected ? FoamyPalette.text : FoamyPalette.secondaryText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.bodySmall
      }
      Equalizer {
        anchors.verticalCenter: parent.verticalCenter
        visible: view.media.showEqualizer === true
        accent: tab.accent
        playing: tab.playing
        // Only while this popup is open (the body is kept after closing).
        animate: view.media.opened === true && !view.editing
      }
    }
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - FoamyStyle.gap * 2
      height: Style.space(2)
      radius: FoamyStyle.pillRadius(height)
      color: Commons.Color.accent
      visible: tab.selected
    }
  }
}
