import QtQuick
import qs.Commons
import "Preferences.js" as Preferences
import "BrowserSetup.js" as BrowserSetup

Column {
  id: root
  required property var candidates
  required property var settings
  required property string language
  property bool saving: false
  property bool expanded: false
  readonly property color secondaryForeground: Qt.tint(Color.popups.background, Qt.alpha(Color.popups.text, 0.7))
  // Derive the summary and checks from persisted settings, not the last clicked row.
  readonly property string selectedLabel: settings.youtubeAppId
    ? BrowserSetup.description(settings.youtubeAppId, Preferences.value(settings, "youtubeProfile")) : ""
  signal apply(var values)
  function tr(text) { return Preferences.text(text, language) }
  function matches(values) {
    return Object.keys(values).every(function(key) { return Preferences.value(root.settings, key) === values[key] })
  }
  function collapse() {
    expanded = false
    header.forceActiveFocus()
  }
  function choose(candidate) {
    if (saving) return
    collapse()
    apply(candidate.values)
  }
  function focusWindow(index) {
    var item = windowRows.itemAt(index)
    if (item) item.forceActiveFocus()
  }
  onVisibleChanged: if (!visible) expanded = false

  Rectangle {
    id: header
    width: parent.width
    height: headerText.implicitHeight + Style.space(18)
    radius: Style.space(6)
    color: headerMouse.containsMouse || activeFocus ? Qt.alpha(Color.popups.text, 0.08) : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.tr("Use an open window") + (root.selectedLabel ? ": " + root.selectedLabel : "")
    Accessible.checkable: true
    Accessible.checked: root.expanded
    Accessible.onPressAction: if (!root.saving) root.expanded = !root.expanded
    function toggle() { if (!root.saving) root.expanded = !root.expanded }
    Keys.onReturnPressed: toggle()
    Keys.onEnterPressed: toggle()
    Keys.onSpacePressed: toggle()
    Keys.onDownPressed: {
      if (!root.saving) {
        root.expanded = true
        root.focusWindow(0)
      }
    }
    Keys.onEscapePressed: function(event) {
      if (root.expanded) root.collapse()
      else event.accepted = false
    }
    Column {
      id: headerText
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(3)
      Text {
        width: parent.width
        text: root.tr("Use an open window")
        color: Color.popups.text
        font.family: "sans-serif"
        font.pixelSize: Style.space(13)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
      }
      Text {
        visible: root.selectedLabel !== ""
        width: parent.width
        text: root.selectedLabel
        color: root.secondaryForeground
        font.family: "sans-serif"
        font.pixelSize: Style.space(12)
        textFormat: Text.PlainText
        elide: Text.ElideRight
      }
    }
    MediaIcon {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(16)
      height: width
      color: root.secondaryForeground
      name: "chevron-right"
      rotation: root.expanded ? 90 : 0
      Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }
    }
    MouseArea {
      id: headerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { header.forceActiveFocus(); header.toggle() }
    }
  }

  Item {
    width: parent.width
    height: root.expanded ? windowColumn.implicitHeight : 0
    clip: true
    // Remove collapsed rows from keyboard navigation immediately, including during animation.
    enabled: root.expanded && !root.saving
    visible: root.expanded || height > 0
    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }
    Column {
      id: windowColumn
      x: Style.space(20)
      width: parent.width - x
      spacing: Style.space(2)
      topPadding: Style.space(4)
      bottomPadding: Style.space(5)
      Text {
        visible: root.candidates.length === 0
        width: parent.width
        padding: Style.space(10)
        text: root.tr("No open YouTube windows")
        color: root.secondaryForeground
        font.family: "sans-serif"
        font.pixelSize: Style.space(12)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
      }
      Repeater {
        id: windowRows
        model: root.candidates
        Rectangle {
          id: windowRow
          required property var modelData
          required property int index
          readonly property bool selected: root.matches(modelData.values)
          readonly property string description: BrowserSetup.description(modelData.id, modelData.values.youtubeProfile)
          width: windowColumn.width
          height: Style.space(54)
          radius: Style.space(6)
          color: windowMouse.containsMouse || activeFocus || selected ? Qt.alpha(Color.popups.text, 0.08) : "transparent"
          border.width: activeFocus ? 1 : 0
          border.color: Color.accent
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.title + ", " + description
          Accessible.onPressAction: root.choose(modelData)
          Keys.onReturnPressed: root.choose(modelData)
          Keys.onEnterPressed: root.choose(modelData)
          Keys.onSpacePressed: root.choose(modelData)
          Keys.onEscapePressed: root.collapse()
          Keys.onUpPressed: index === 0 ? header.forceActiveFocus() : root.focusWindow(index - 1)
          Keys.onDownPressed: root.focusWindow(Math.min(windowRows.count - 1, index + 1))
          MediaIcon {
            id: windowIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: width
            name: "app-window"
            color: root.secondaryForeground
          }
          Column {
            anchors.left: windowIcon.right
            anchors.right: check.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: windowRow.modelData.title
              font.family: "sans-serif"
              font.pixelSize: Style.space(13)
              color: Color.popups.text
              textFormat: Text.PlainText
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: windowRow.description
              font.family: "sans-serif"
              font.pixelSize: Style.space(12)
              color: root.secondaryForeground
              textFormat: Text.PlainText
              elide: Text.ElideRight
            }
          }
          MediaIcon {
            id: check
            visible: windowRow.selected
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: width
            name: "check"
            color: Color.accent
          }
          MouseArea {
            id: windowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.choose(windowRow.modelData)
          }
        }
      }
    }
  }
}
