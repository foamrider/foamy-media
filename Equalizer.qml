import QtQuick
import qs.Commons
import qs.Commons as Commons
import "kit"

// The three-stem playback equalizer in the bar and on the popup's source tabs.
//
// It steps through a short keyframe table at about 8 Hz instead of animating
// continuously: a NumberAnimation would redraw the bar at the display's frame
// rate for as long as music plays, while eight discrete steps a second read
// the same at this size. Stems only move while `animate` is true (the bar is
// shown, or the popup is open), something is playing, and reduced motion is
// off; otherwise they rest at a still "playing" or idle shape.
Item {
  id: root

  property color accent: Commons.Color.accent
  property bool playing: false
  // The caller's visibility gate (bar shown / popup open).
  property bool animate: true
  property bool showIdle: true

  readonly property bool stepping: playing && animate && visible && !FoamyMotion.reduceMotion
  // Heights in Style.space units, one row per step.
  readonly property var frames: [[3, 7, 5], [6, 4, 8], [8, 2, 6], [5, 5, 3], [2, 8, 5], [4, 6, 8], [7, 3, 4], [5, 7, 2]]
  readonly property var still: playing ? [5, 7, 4] : [3, 3, 3]
  property int frame: 0
  readonly property var heights: stepping ? frames[frame % frames.length] : still

  implicitWidth: Style.space(10)
  implicitHeight: Style.space(9)
  opacity: playing || showIdle ? 1 : 0

  Behavior on opacity { NumberAnimation { duration: FoamyMotion.toggle } }

  Timer {
    interval: 125
    repeat: true
    running: root.stepping
    onTriggered: root.frame = (root.frame + 1) % root.frames.length
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    height: parent.height
    spacing: Style.space(1)

    Repeater {
      model: 3
      Item {
        id: stem
        required property int index
        width: Style.space(2)
        height: parent.height
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(root.heights[stem.index])
          radius: FoamyStyle.pillRadius(width)
          color: root.accent
        }
      }
    }
  }
}
