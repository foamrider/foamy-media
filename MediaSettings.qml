pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "kit/FoamyPrefs.js" as Prefs
import "Preferences.js" as Schema

// The settings page: controls, bar, panel and YouTube browser settings on
// the foamy settings skeleton. Reads and saves through `media` (the Panel or
// the preview mock): media.settings, media.save(key, value),
// media.saveMany(values), media.saving, media.settingsError, media.retryable.
FoamySettingsPage {
  id: page

  required property var media
  readonly property var settings: media.effectiveSettings || media.settings || ({})
  function value(key) { return Prefs.value(Schema.schema, page.settings, key) }
  function label(key) { return FoamyI18n.t(Schema.labels[key]) }

  property bool browserAdvancedOpen: false
  readonly property alias browserSection: browserColumn
  onVisibleChanged: if (!visible) browserAdvancedOpen = false

  saving: media.saving === true
  error: media.settingsError ? FoamyI18n.t(media.settingsError) : ""
  retryable: media.retryable === true
  onBack: media.closeSettings()
  onRetry: media.retrySave()

  FoamySettingsSection {
    width: parent.width
    title: FoamyI18n.t("Controls")
    FoamyToggle {
      width: parent.width
      label: page.label("leftClick")
      description: FoamyI18n.t(page.value("leftClick") === "Play/pause" ? "Right-click opens the popup." : "Left-click opens the popup.")
      checked: page.value("leftClick") === "Play/pause"
      enabled: !page.saving
      onClicked: page.media.save("leftClick", checked ? "Open panel" : "Play/pause")
    }
    FoamyDropdown {
      width: parent.width
      label: page.label("scrollAction")
      value: page.value("scrollAction")
      options: Prefs.field(Schema.schema, "scrollAction").options.map(function(option) { return { value: option, label: FoamyI18n.t(option) } })
      onChanged: function(next) { page.media.save("scrollAction", next) }
    }
    NumberRow { key: "volumeStep"; visible: page.value("scrollAction") === "Volume" }
    FoamyToggle {
      width: parent.width
      label: page.label("hideWhenClosed")
      description: FoamyI18n.t("Paused tracks stay visible.")
      checked: page.value("hideWhenClosed") === true
      enabled: !page.saving
      onClicked: page.media.save("hideWhenClosed", !checked)
    }
  }

  FoamySettingsSection {
    width: parent.width
    title: FoamyI18n.t("Bar")
    BoolRow { key: "showArtist" }
    BoolRow { key: "showProgress" }
    BoolRow { key: "animateTitle" }
    BoolRow { key: "showEqualizer" }
    NumberRow { key: "maxLabelWidth" }
  }

  FoamySettingsSection {
    width: parent.width
    title: FoamyI18n.t("Appearance")
    FoamyDropdown {
      width: parent.width
      label: page.label("accent")
      value: page.value("accent")
      options: Prefs.field(Schema.schema, "accent").options.map(function(option) { return { value: option, label: FoamyI18n.t(option) } })
      onChanged: function(next) { page.media.save("accent", next) }
    }
    BoolRow { key: "artBackground" }
    NumberRow { key: "artIntensity"; visible: page.value("artBackground") === true }
  }

  FoamySettingsSection {
    width: parent.width
    title: FoamyI18n.t("YouTube")
    BoolRow { key: "youtubeEnabled" }
    FoamyAction {
      visible: page.value("youtubeEnabled") === true
      focusable: true
      iconName: page.media.browserSettingsOpen ? "chevron-down" : "chevron-right"
      label: FoamyI18n.t("Browser settings")
      foreground: FoamyPalette.secondaryText
      onClicked: page.media.browserSettingsOpen = !page.media.browserSettingsOpen
    }
    Column {
      id: browserColumn
      visible: page.value("youtubeEnabled") === true && page.media.browserSettingsOpen === true
      width: parent.width
      spacing: FoamyStyle.gap
      BrowserPicker {
        width: parent.width
        candidates: page.media.browserCandidates || []
        settings: page.settings
        saving: page.saving
        onApply: function(values) { page.media.saveMany(values) }
      }
      TextRow { key: "youtubeBrowser" }
      TextRow { key: "youtubeProfile" }
      FoamyAction {
        focusable: true
        iconName: page.browserAdvancedOpen ? "chevron-down" : "chevron-right"
        label: FoamyI18n.t("Advanced")
        foreground: FoamyPalette.secondaryText
        onClicked: page.browserAdvancedOpen = !page.browserAdvancedOpen
      }
      TextRow { key: "youtubeAppId"; visible: page.browserAdvancedOpen }
      TextRow { key: "youtubeMprisName"; visible: page.browserAdvancedOpen }
    }
  }

  // ---- Rows ----------------------------------------------------------------
  component BoolRow: FoamyToggle {
    required property string key
    width: parent ? parent.width : 0
    label: page.label(key)
    checked: page.value(key) === true
    enabled: !page.saving
    onClicked: page.media.save(key, !checked)
  }

  component SettingLabel: Text {
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignLeft
    wrapMode: Text.WordWrap
    color: Commons.Color.popups.text
    font.family: FoamyStyle.fontFamily
    font.pixelSize: FoamyStyle.font.subtitle
  }

  // An integer setting: label and a short field; Enter or leaving saves.
  component NumberRow: RowLayout {
    id: numberRow
    required property string key
    readonly property var spec: Prefs.field(Schema.schema, key)
    readonly property var current: page.value(key)
    width: parent ? parent.width : 0
    spacing: FoamyStyle.gapLarge
    SettingLabel {
      Layout.fillWidth: true
      text: page.label(numberRow.key)
    }
    SafeTextField {
      id: numberInput
      Layout.preferredWidth: Style.space(72)
      implicitHeight: FoamyStyle.controlHeight
      text: String(numberRow.current)
      horizontalAlignment: Text.AlignHCenter
      font.family: FoamyStyle.fontFamily
      font.pixelSize: FoamyStyle.font.body
      enabled: !page.saving
      translate: FoamyI18n.t
      Accessible.name: page.label(numberRow.key)
      onPasteErrorChanged: if (pasteError !== "") page.media.showError(pasteError)
      onEditingFinished: {
        if (!numberRow.visible) return
        var next = Number(text.trim())
        if (text.trim() === "" || next === numberRow.current) { text = String(numberRow.current); return }
        page.media.save(numberRow.key, next)
        if (!Prefs.valid(Schema.schema, numberRow.key, next)) text = String(numberRow.current)
      }
      onKeyPressed: function(event) {
        if (event.key === Qt.Key_Escape) { text = String(numberRow.current); page.back(); event.accepted = true }
      }
      HoverHandler { id: numberHover }
      PanelToolTip {
        visible: numberHover.hovered || numberInput.inputActiveFocus
        text: FoamyI18n.t("%1–%2", [FoamyI18n.number(numberRow.spec.min), FoamyI18n.number(numberRow.spec.max)])
        fontFamily: FoamyStyle.fontFamily
      }
    }
  }

  // A string setting: label and a field; Enter or leaving saves.
  component TextRow: RowLayout {
    id: textRow
    required property string key
    readonly property string current: String(page.value(key))
    width: parent ? parent.width : 0
    spacing: FoamyStyle.gapLarge
    SettingLabel {
      Layout.preferredWidth: Style.space(96)
      text: page.label(textRow.key)
    }
    SafeTextField {
      id: valueInput
      Layout.fillWidth: true
      implicitHeight: FoamyStyle.controlHeight
      text: textRow.current
      font.family: FoamyStyle.fontFamily
      font.pixelSize: FoamyStyle.font.body
      enabled: !page.saving
      translate: FoamyI18n.t
      Accessible.name: page.label(textRow.key)
      onPasteErrorChanged: if (pasteError !== "") page.media.showError(pasteError)
      onEditingFinished: {
        if (!textRow.visible) return
        var next = text.trim()
        if (next === textRow.current) return
        page.media.save(textRow.key, next)
        if (!Prefs.valid(Schema.schema, textRow.key, next)) text = textRow.current
      }
      onKeyPressed: function(event) {
        if (event.key === Qt.Key_Escape) { text = textRow.current; page.back(); event.accepted = true }
      }
    }
  }
}
