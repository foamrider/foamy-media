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
  property var browserCandidates: []
  signal applyBrowser(var values)
  readonly property color secondaryForeground: Qt.tint(Color.popups.background, Qt.alpha(Color.popups.text, 0.7))
  property bool saving: false
  property string error: ""
  property bool browserSettingsOpen: false
  property bool browserAdvancedOpen: false
  onBrowserSettingsOpenChanged: if (!browserSettingsOpen) browserAdvancedOpen = false
  onVisibleChanged: if (!visible) browserSettingsOpen = false
  property alias backTarget: backButton
  signal save(string key, var value)
  signal back()
  signal clearError()
  function tr(text) { return Preferences.text(text, language) }
  function focusBack() { backButton.forceActiveFocus() }
  spacing: Style.space(12)
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
    MediaAction {
      id: backButton
      iconName: "arrow-left"
      tooltipText: root.tr("Back")
      foreground: root.secondaryForeground
      Accessible.name: tooltipText
      onClicked: root.back()
    }
    SettingLabel {
      text: root.tr("Settings")
      color: root.secondaryForeground
      Layout.fillWidth: true
    }
    SettingLabel {
      visible: root.saving
      text: root.tr("Saving…")
      font.pixelSize: Style.space(11)
      color: root.secondaryForeground
    }
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
      {title:"YouTube", keys:["youtubeEnabled", "youtubeBrowser", "youtubeProfile", "youtubeAppId", "youtubeMprisName"]}
    ]
    Column {
      id: group
      required property var modelData
      width: root.width - root.padding * 2
      spacing: Style.space(8)
      SettingLabel { text: root.tr(group.modelData.title); font.bold: true }
      Repeater {
        model: group.modelData.keys
        Column {
          id: fieldRow
          required property string modelData
          readonly property var spec: Preferences.field(modelData)
          readonly property var current: Preferences.value(root.settings, modelData)
          readonly property bool isClick: modelData === "leftClick"
          readonly property bool browserDetail: modelData.indexOf("youtube") === 0 && modelData !== "youtubeEnabled"
          readonly property bool advancedDetail: modelData === "youtubeAppId" || modelData === "youtubeMprisName"
          readonly property string shortLabel: root.tr(Preferences.labels[modelData] || spec.label)
          visible: browserDetail ? root.browserSettingsOpen && Preferences.value(root.settings, "youtubeEnabled")
              && (!advancedDetail || root.browserAdvancedOpen)
            : modelData === "volumeStep" ? Preferences.value(root.settings, "scrollAction") === "Volume"
            : modelData === "artIntensity" ? Preferences.value(root.settings, "artBackground") : true
          width: group.width
          spacing: Style.space(5)
          // Keep the accordion header focused while its detected values are saved.
          enabled: (!root.saving || modelData === "youtubeEnabled") && (modelData.indexOf("youtube") !== 0 || modelData === "youtubeEnabled"
            || Preferences.value(root.settings, "youtubeEnabled"))
          opacity: enabled ? 1 : 0.55

          Toggle {
            visible: fieldRow.spec.type === "boolean" || fieldRow.isClick
            width: parent.width
            id: settingToggle
            enabled: !root.saving
            implicitHeight: Style.space(36)
            borderSpec: activeFocus ? Border.flat(Color.accent, 1) : Border.none()
            color: "transparent"
            radius: Style.space(7)
            titleSize: Style.space(13)
            fontFamily: "sans-serif"
            label: fieldRow.shortLabel
            property bool showHint: false
            onHovered: function(hovered) { showHint = hovered }
            PanelToolTip {
              visible: fieldRow.isClick && (settingToggle.showHint || settingToggle.activeFocus)
              text: root.tr(fieldRow.current === "Play/pause" ? "Right-click opens the popup." : "Left-click opens the popup.")
              fontFamily: "sans-serif"
            }
            checked: fieldRow.isClick ? fieldRow.current === "Play/pause" : fieldRow.current === true
            Accessible.name: label
            onClicked: root.save(fieldRow.modelData, fieldRow.isClick
              ? (checked ? "Open panel" : "Play/pause") : !checked)
          }
          MediaAction {
            visible: fieldRow.modelData === "youtubeEnabled" && Preferences.value(root.settings, "youtubeEnabled")
            label: root.tr("Browser settings")
            iconName: root.browserSettingsOpen ? "chevron-down" : "chevron-right"
            foreground: root.secondaryForeground
            onClicked: root.browserSettingsOpen = !root.browserSettingsOpen
          }
          BrowserPicker {
            visible: fieldRow.modelData === "youtubeEnabled" && root.browserSettingsOpen
              && Preferences.value(root.settings, "youtubeEnabled")
            width: parent.width
            candidates: root.browserCandidates
            settings: root.settings
            language: root.language
            saving: root.saving
            onApply: function(values) { root.applyBrowser(values) }
          }
          MediaDropdown {
            visible: fieldRow.spec.type === "enum" && !fieldRow.isClick
            width: parent.width
            fontFamily: "sans-serif"
            label: fieldRow.shortLabel
            value: String(fieldRow.current)
            options: (fieldRow.spec.options || []).map(function(value) { return {value:value, label:root.tr(value)} })
            onChanged: function(value) { root.save(fieldRow.modelData, value) }
          }
          RowLayout {
            visible: fieldRow.spec.type === "integer"
            width: parent.width
            spacing: Style.space(12)
            SettingLabel {
              text: fieldRow.shortLabel
              Layout.fillWidth: true
            }
            Controls.TextField {
              id: numberInput
              Layout.preferredWidth: Style.space(72)
              implicitHeight: Style.space(32)
              text: String(fieldRow.current)
              selectByMouse: true
              horizontalAlignment: Text.AlignHCenter
              color: Color.popups.text
              font.family: "sans-serif"
              font.pixelSize: Style.space(12)
              padding: Style.space(6)
              Accessible.name: fieldRow.shortLabel
              background: Rectangle {
                radius: Style.space(7)
                color: Qt.alpha(Color.popups.text, 0.055)
                border.width: numberInput.activeFocus ? 1 : 0
                border.color: Color.accent
              }
              onTextEdited: root.clearError()
              onEditingFinished: {
                if (!visible) return
                if (Number(text) !== fieldRow.current) root.save(fieldRow.modelData, Number(text))
              }
              Keys.onEscapePressed: { text = String(fieldRow.current); root.back() }
              HoverHandler { id: numberHover }
              PanelToolTip {
                visible: numberHover.hovered || numberInput.activeFocus
                text: String(fieldRow.spec.min || 0) + "–" + String(fieldRow.spec.max || 0)
                fontFamily: "sans-serif"
              }
            }
          }
          RowLayout {
            visible: fieldRow.spec.type === "string"
            width: parent.width
            spacing: Style.space(12)
            SettingLabel {
              text: fieldRow.shortLabel
              Layout.preferredWidth: Style.space(80)
            }
            Controls.TextField {
              id: valueInput
              Layout.fillWidth: true
              implicitHeight: Style.space(34)
              text: String(fieldRow.current)
              selectByMouse: true
              color: Color.popups.text
              font.family: "sans-serif"
              font.pixelSize: Style.space(12)
              padding: Style.space(8)
              Accessible.name: fieldRow.shortLabel
              background: Rectangle {
                radius: Style.space(7)
                color: "transparent"
                border.width: 1
                border.color: valueInput.activeFocus ? Color.accent : Qt.alpha(Color.popups.text, 0.22)
              }
              onTextEdited: root.clearError()
              onEditingFinished: {
                if (!visible) return
                if (text.trim() !== fieldRow.current) root.save(fieldRow.modelData, text.trim())
              }
              Keys.onEscapePressed: { text = String(fieldRow.current); root.back() }
            }
          }
          MediaAction {
            visible: fieldRow.modelData === "youtubeProfile"
            label: root.tr("Advanced")
            iconName: root.browserAdvancedOpen ? "chevron-down" : "chevron-right"
            foreground: root.secondaryForeground
            onClicked: root.browserAdvancedOpen = !root.browserAdvancedOpen
          }
        }
      }
    }
  }
}
