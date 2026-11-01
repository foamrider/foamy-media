import QtQuick
import qs.Commons
import qs.Commons as Commons
import "kit"

// What the media widget paints in the bar: the source glyph, the track label
// (panning when it does not fit), the equalizer and a thin progress
// underline. Pure presentation, fed by Panel.qml (and by preview/Preview.qml
// with mock data).
//
// Cost while music plays: the label pans only while playing, with the popup
// closed and reduced motion off (otherwise it rests elided at its start); the
// equalizer steps at 8 Hz; the underline moves without an animation, and only
// as often as it gains a pixel (Panel.qml's position tick).
Item {
  id: root

  property bool vertical: false
  property int barSize: Style.bar.sizeHorizontal
  property string fontFamily: Style.font.family
  property string glyph: ""
  property color glyphColor: Commons.Color.foreground
  property bool colorAnimation: true
  property string label: ""
  property color labelColor: Commons.Color.foreground
  property real maxLabelWidth: Style.space(200)
  property bool animateTitle: true
  property bool live: false
  property bool playing: false
  property bool showEqualizer: true
  property color accent: Commons.Color.accent
  property bool showProgress: true
  property real progress: 0
  // The popup is open: the bar's open-panel mark sits where the underline
  // would be, and the popup shows the timeline anyway.
  property bool popupOpen: false

  readonly property bool progressShown: progressLine.visible
  readonly property real progressWidth: Math.max(1, width - Style.space(12))
  readonly property bool panning: marquee.running

  readonly property real labelSlot: labelClip.visible ? labelClip.width + Style.space(6) : 0
  readonly property real equalizerSlot: barEqualizer.visible ? barEqualizer.implicitWidth + Style.space(6) : 0
  implicitWidth: vertical ? barSize : Math.round(glyphText.implicitWidth + labelSlot + equalizerSlot + Style.space(12))
  implicitHeight: vertical ? Math.round(glyphText.implicitHeight + Style.space(10)) : barSize

  Row {
    anchors.centerIn: parent
    spacing: root.vertical ? 0 : Style.space(6)

    Text {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.glyph
      color: root.glyphColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body

      Behavior on color {
        enabled: root.colorAnimation
        ColorAnimation { duration: FoamyMotion.press }
      }
    }

    Item {
      id: labelClip
      objectName: "mediaBarLabel"
      visible: !root.vertical && root.label !== ""
      width: visible ? Math.min(root.maxLabelWidth, labelMetrics.naturalWidth) : 0
      height: glyphText.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      // The slot is sized from a separate measurement, not from labelText's
      // own implicitWidth: that binding loop resized the text in the middle
      // of its layout, so a title that grew (Spotify sends the artist after
      // the title) kept the ellipsis of the shorter text.
      TextMetrics {
        id: labelMetrics
        readonly property real naturalWidth: Math.ceil(advanceWidth)
        font: labelText.font
        text: root.label
      }

      // The title sits at the start and stays readable. Only a title too long
      // for the slot pans, and it rests at both ends before turning around,
      // so glancing at the bar always catches the beginning of a track.
      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.label
        color: root.labelColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        // At rest the label is cut to the slot with an ellipsis; panning it
        // shows the whole title.
        width: root.panning ? labelMetrics.naturalWidth : labelClip.width
        elide: root.panning ? Text.ElideNone : Text.ElideRight
        // Text direction determines which end contains the beginning of the title.
        readonly property real panX: horizontalAlignment === Text.AlignRight ? panOffset-overflow : -panOffset
        x: root.panning ? panX : 0

        property real panOffset: 0
        readonly property real overflow: Math.max(0, labelMetrics.naturalWidth - labelClip.width)

        onTextChanged: {
          panOffset = 0
          if (marquee.running) marquee.restart()
        }
      }

      SequentialAnimation {
        id: marquee
        running: root.animateTitle && root.playing && !root.popupOpen && labelText.overflow > 0
          && labelClip.visible && root.visible && !FoamyMotion.reduceMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) labelText.panOffset = 0

        PauseAnimation { duration: FoamyMotion.duration(2600) }
        NumberAnimation {
          target: labelText
          property: "panOffset"
          from: 0
          to: labelText.overflow
          duration: FoamyMotion.duration(Math.max(1600, labelText.overflow * 45))
          easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: FoamyMotion.duration(2200) }
        NumberAnimation {
          target: labelText
          property: "panOffset"
          from: labelText.overflow
          to: 0
          duration: FoamyMotion.duration(Math.max(900, labelText.overflow * 20))
          easing.type: Easing.InOutQuad
        }
      }
    }

    Equalizer {
      id: barEqualizer
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showEqualizer && !root.vertical && root.live
      accent: root.accent
      playing: root.playing
      animate: root.visible
    }
  }

  // Thin now-playing underline along the bottom of the widget.
  Rectangle {
    id: progressLine
    objectName: "mediaProgressLine"
    visible: root.showProgress && root.live && !root.vertical && !root.popupOpen
    x: Style.space(6)
    width: Math.round(root.progressWidth * Math.max(0, Math.min(1, root.progress)))
    height: Math.max(1, Style.space(2))
    radius: FoamyStyle.pillRadius(height)
    color: root.accent
    opacity: root.playing ? 0.95 : 0.5
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2)

    Behavior on opacity { NumberAnimation { duration: FoamyMotion.press } }
  }
}
