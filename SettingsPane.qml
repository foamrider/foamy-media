import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "Preferences.js" as Preferences

Column {
  id: root
  required property var settings
  required property string language
  property bool saving: false
  property string error: ""
  property alias backTarget: backButton
  signal save(string key, var value)
  signal back()
  signal clearError()
  function tr(text) { return Preferences.text(text, language) }
  function focusBack() { backButton.forceActiveFocus() }
  spacing: Style.space(18)
  padding: Style.space(20)

  component SettingLabel: Text {
    color: Color.popups.text
    font.family: "sans-serif"
    font.pixelSize: Style.space(13)
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
  }

  RowLayout {
    width: parent.width - root.padding * 2
    PanelActionButton {
      id: backButton
      iconText: "󰁍"
      tooltipText: root.tr("Back")
      focusable: true
      size: Style.space(30)
      Accessible.name: tooltipText
      onClicked: root.back()
    }
    SettingLabel {
      text: root.tr("Settings")
      font.pixelSize: Style.space(19)
      Layout.fillWidth: true
    }
  }
  SettingLabel {
    width: parent.width - root.padding * 2
    text: root.saving ? root.tr("Saving…") : root.tr("Settings are saved automatically.")
    color: Qt.alpha(Color.popups.text, 0.7)
    font.pixelSize: Style.space(11)
  }
  SettingLabel {
    width: parent.width - root.padding * 2
    visible: root.error !== ""
    text: root.error
    Accessible.role: Accessible.AlertMessage
  }
  MediaDropdown {
    width: parent.width - root.padding * 2
    fontFamily: "sans-serif"
    label: root.tr("Language")
    value: Preferences.value(root.settings, "language")
    options: [{value:"system", label:root.tr("Default (system language)")},
      {value:"nb", label:"Norsk bokmål"}, {value:"en", label:"English"}]
    enabled: !root.saving
    onChanged: function(value) { root.save("language", value) }
  }

  Repeater {
    model: [
      {title:"Controls", keys:["leftClick", "scrollAction", "volumeStep", "hideWhenClosed"]},
      {title:"Appearance", keys:["maxLabelWidth", "showArtist", "showProgress", "animateTitle", "showEqualizer", "accent", "artBackground", "artIntensity"]},
      {title:"YouTube integration", keys:["youtubeEnabled", "youtubeBrowser", "youtubeProfile", "youtubeAppId", "youtubeMprisName"]}
    ]
    Column {
      id: group
      required property var modelData
      width: root.width - root.padding * 2
      spacing: Style.space(10)
      SettingLabel { text: root.tr(group.modelData.title); font.bold: true }
      SettingLabel {
        visible: group.modelData.title === "YouTube integration"
        width: parent.width
        text: root.tr("These identifiers must match the dedicated YouTube web app and its browser.")
        color: Qt.alpha(Color.popups.text, 0.7)
        font.pixelSize: Style.space(11)
      }
      Repeater {
        model: group.modelData.keys
        Column {
          id: fieldRow
          required property string modelData
          readonly property var spec: Preferences.field(modelData)
          readonly property var current: Preferences.value(root.settings, modelData)
          readonly property bool isClick: modelData === "leftClick"
          width: group.width
          spacing: Style.space(5)
          enabled: !root.saving && (modelData.indexOf("youtube") !== 0 || modelData === "youtubeEnabled"
            || Preferences.value(root.settings, "youtubeEnabled"))
          opacity: enabled ? 1 : 0.55

          Toggle {
            visible: fieldRow.spec.type === "boolean" || fieldRow.isClick
            width: parent.width
            implicitHeight: Style.space(fieldRow.isClick ? 60 : 40)
            radius: Style.space(7)
            titleSize: Style.space(13)
            fontFamily: "sans-serif"
            label: root.tr(fieldRow.isClick ? "Left-click plays/pauses" : fieldRow.spec.label)
            description: fieldRow.isClick ? root.tr(fieldRow.current === "Play/pause"
              ? "Right-click opens the popup." : "Left-click opens the popup.") : ""
            checked: fieldRow.isClick ? fieldRow.current === "Play/pause" : fieldRow.current === true
            Accessible.name: label
            onClicked: root.save(fieldRow.modelData, fieldRow.isClick
              ? (checked ? "Open panel" : "Play/pause") : !checked)
          }
          MediaDropdown {
            visible: fieldRow.spec.type === "enum" && !fieldRow.isClick
            width: parent.width
            fontFamily: "sans-serif"
            label: root.tr(fieldRow.spec.label)
            value: String(fieldRow.current)
            options: (fieldRow.spec.options || []).map(function(value) { return {value:value, label:root.tr(value)} })
            onChanged: function(value) { root.save(fieldRow.modelData, value) }
          }
          SettingLabel {
            visible: fieldRow.spec.type === "integer" || fieldRow.spec.type === "string"
            width: parent.width
            text: root.tr(fieldRow.spec.label)
            font.pixelSize: Style.space(12)
          }
          Controls.TextField {
            id: valueInput
            visible: fieldRow.spec.type === "integer" || fieldRow.spec.type === "string"
            width: parent.width
            implicitHeight: Style.space(34)
            text: String(fieldRow.current)
            selectByMouse: true
            color: Color.popups.text
            font.family: "sans-serif"
            font.pixelSize: Style.space(12)
            padding: Style.space(8)
            Accessible.name: root.tr(fieldRow.spec.label)
            background: Rectangle {
              radius: Style.space(7)
              color: Qt.alpha(Color.popups.text, 0.055)
              border.width: 1
              border.color: valueInput.activeFocus ? Color.accent : Qt.alpha(Color.popups.text, 0.22)
            }
            onTextEdited: root.clearError()
            onEditingFinished: {
              if (!visible) return
              var value = fieldRow.spec.type === "integer" ? Number(text) : text.trim()
              if (value !== fieldRow.current) root.save(fieldRow.modelData, value)
            }
            Keys.onEscapePressed: { text = String(fieldRow.current); root.back() }
          }
          SettingLabel {
            visible: fieldRow.spec.type === "integer"
            text: String(fieldRow.spec.min || 0) + "–" + String(fieldRow.spec.max || 0)
            color: Qt.alpha(Color.popups.text, 0.55)
            font.pixelSize: Style.space(10)
          }
        }
      }
    }
  }
}
