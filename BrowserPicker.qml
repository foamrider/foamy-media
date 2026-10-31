import QtQuick
import qs.Commons
import qs.Commons as Commons
import "kit"
import "kit/FoamyPrefs.js" as Prefs
import "Preferences.js" as Schema
import "BrowserSetup.js" as BrowserSetup

// "Use an open window": lists the open YouTube web-app windows and offers
// the browser, profile, app ID and MPRIS name each implies. A settings-form
// control (Tab, arrows and Enter inside the picker), not a cursor row.

Column {
  id: root
  required property var candidates
  required property var settings
  property bool saving: false
  property bool expanded: false
  readonly property color secondaryForeground: FoamyPalette.secondaryText
  // Derive the summary and checks from persisted settings, not the last clicked row.
  readonly property string selectedLabel: settings.youtubeAppId
    ? BrowserSetup.description(settings.youtubeAppId, Prefs.value(Schema.schema, settings, "youtubeProfile")) : ""
  signal apply(var values)
  function tr(text) { return FoamyI18n.t(text) }
  function matches(values) {
    return Object.keys(values).every(function(key) { return Prefs.value(Schema.schema, root.settings, key) === values[key] })
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
    objectName: "browserPickerHeader"
    width: parent.width
    height: headerText.implicitHeight + Style.space(18)
    radius: FoamyStyle.radius
    color: headerMouse.containsMouse || activeFocus ? FoamyPalette.hoverFill : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: Commons.Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.tr("Use an open window") + (root.selectedLabel ? ": " + root.selectedLabel : "")
    Accessible.checkable: true
    Accessible.checked: root.expanded
    Accessible.onPressAction: if (!root.saving) root.expanded = !root.expanded
    function toggle() { if (!root.saving) root.expanded = !root.expanded }
    // Expand toward the reading direction; collapse toward the leading edge.
    Keys.onPressed: function(event) {
      if (event.key === (FoamyI18n.rightToLeft ? Qt.Key_Left : Qt.Key_Right) && !root.saving) {
        root.expanded = true; root.focusWindow(0); event.accepted = true
      } else if (event.key === (FoamyI18n.rightToLeft ? Qt.Key_Right : Qt.Key_Left) && root.expanded) {
        root.collapse(); event.accepted = true
      }
    }
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
      anchors.rightMargin: FoamyStyle.gapLarge
      spacing: Style.space(3)
      Text {
        width: parent.width
        text: root.tr("Use an open window")
        color: FoamyPalette.text
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.subtitle
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
      }
      Text {
        visible: root.selectedLabel !== ""
        width: parent.width
        text: root.selectedLabel
        color: root.secondaryForeground
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.body
        textFormat: Text.PlainText
        elide: Text.ElideRight
      }
    }
    FoamyIcon {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      width: FoamyStyle.iconSize
      height: width
      color: root.secondaryForeground
      name: "chevron-right"
      rotation: root.expanded ? (FoamyI18n.rightToLeft ? -90 : 90) : 0
      Behavior on rotation { NumberAnimation { duration: FoamyMotion.press; easing.type: Easing.InOutQuad } }
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
    Behavior on height { NumberAnimation { duration: FoamyMotion.press; easing.type: Easing.InOutQuad } }
    Column {
      id: windowColumn
      objectName: "browserWindowList"
      anchors.left: parent.left
      anchors.leftMargin: FoamyStyle.padding
      anchors.right: parent.right
      spacing: FoamyStyle.gapTiny
      topPadding: FoamyStyle.gapSmall
      bottomPadding: Style.space(5)
      Text {
        visible: root.candidates.length === 0
        width: parent.width
        padding: FoamyStyle.rowPadding
        text: root.tr("No open YouTube windows")
        color: root.secondaryForeground
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.body
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
          radius: FoamyStyle.radius
          color: windowMouse.containsMouse || activeFocus || selected ? FoamyPalette.hoverFill : "transparent"
          border.width: activeFocus ? 1 : 0
          border.color: Commons.Color.accent
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.title + ", " + description
          Accessible.onPressAction: root.choose(modelData)
          Keys.onPressed: function(event) {
            if (event.key === (FoamyI18n.rightToLeft ? Qt.Key_Right : Qt.Key_Left)) {
              root.collapse(); event.accepted = true
            }
          }
          Keys.onReturnPressed: root.choose(modelData)
          Keys.onEnterPressed: root.choose(modelData)
          Keys.onSpacePressed: root.choose(modelData)
          Keys.onEscapePressed: root.collapse()
          Keys.onUpPressed: index === 0 ? header.forceActiveFocus() : root.focusWindow(index - 1)
          Keys.onDownPressed: root.focusWindow(Math.min(windowRows.count - 1, index + 1))
          FoamyIcon {
            id: windowIcon
            anchors.left: parent.left
            anchors.leftMargin: FoamyStyle.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            width: FoamyStyle.iconSize
            height: width
            name: "app-window"
            color: root.secondaryForeground
          }
          Column {
            anchors.left: windowIcon.right
            anchors.right: check.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: FoamyStyle.rowPadding
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: windowRow.modelData.title
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.subtitle
              color: FoamyPalette.text
              textFormat: Text.PlainText
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: windowRow.description
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.body
              color: root.secondaryForeground
              textFormat: Text.PlainText
              elide: Text.ElideRight
            }
          }
          FoamyIcon {
            id: check
            visible: windowRow.selected
            anchors.right: parent.right
            anchors.rightMargin: FoamyStyle.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            width: FoamyStyle.iconSize
            height: width
            name: "check"
            color: Commons.Color.accent
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
