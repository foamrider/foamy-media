import QtQuick
import QtQuick.Controls.Basic
import qs.Commons as Commons
import "kit"

// The seek and volume slider, drawn like foamy-audio's AudioSlider so the
// two popups match: a thin track with the accent fill and a light thumb.
// The panel cursor on a slider rings the thumb and lifts the track; there is
// never a filled row behind it (DESIGN.md "Sliders").
//
// `value` follows `current` except while the thumb is held, so playback
// ticks don't pull it from under the pointer. `moved()` fires while
// dragging (volume follows it); `committed(value)` fires on release and on a
// wheel step (seeking waits for it). The wheel over a slider moves it by
// `stepSize` per notch; the keyboard goes through the panel cursor (h/l).
Slider {
  id: root
  property string label: ""
  property bool hasCursor: false
  property real current: 0
  signal committed(real value)

  from: 0
  to: 1
  focusPolicy: Qt.NoFocus
  wheelEnabled: true
  implicitHeight: Commons.Style.space(24)
  padding: 0
  opacity: enabled ? 1 : FoamyStyle.disabledOpacity
  Accessible.name: label

  Binding {
    target: root
    property: "value"
    value: root.current
    when: !root.pressed
    restoreMode: Binding.RestoreNone
  }
  onPressedChanged: if (!pressed) committed(value)
  onMoved: if (!pressed) committed(value)

  HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

  background: Rectangle {
    x: root.leftPadding
    y: (root.height - height) / 2
    width: root.availableWidth
    height: Commons.Style.space(4)
    radius: height / 2
    color: Qt.alpha(Commons.Color.popups.text, root.hasCursor ? 0.28 : 0.18)
    Behavior on color { ColorAnimation { duration: FoamyMotion.hover } }
    Rectangle {
      x: root.mirrored ? parent.width - width : 0
      width: root.position * parent.width
      height: parent.height
      radius: parent.radius
      color: Commons.Color.accent
    }
  }
  handle: Rectangle {
    x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
    y: (root.height - height) / 2
    width: Commons.Style.space(11)
    height: width
    radius: width / 2
    color: Commons.Color.popups.text
    // The cursor ring around the thumb.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width + Commons.Style.space(8)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1, Commons.Style.space(2))
      border.color: Commons.Color.accent
      opacity: root.hasCursor ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: FoamyMotion.hover } }
    }
  }
}
