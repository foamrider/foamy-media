pragma ComponentBehavior: Bound
import QtQuick
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

  // An integer setting. The kit field shows the saved value (following
  // changes made elsewhere: another monitor, the bar editor), keeps a draft
  // while you type and commits a valid, changed number once on Enter or
  // focus-out; the first Escape restores the value and stays on the page.
  component NumberRow: FoamyNumberField {
    id: numberRow
    required property string key
    readonly property var spec: Prefs.field(Schema.schema, key)
    width: parent ? parent.width : 0
    label: page.label(key)
    unit: Schema.units[key] || ""
    value: page.value(key)
    from: spec.min
    to: spec.max
    stepSize: spec.step || 1
    enabled: !page.saving
    onCommitted: function(next) { page.media.save(numberRow.key, next) }
  }

  // A string setting, same rules; the draft is checked against the schema
  // (the browser and MPRIS name must be bare program names).
  component TextRow: FoamyTextSettingField {
    id: textRow
    required property string key
    width: parent ? parent.width : 0
    label: page.label(key)
    value: String(page.value(key))
    validate: function(text) { return Prefs.valid(Schema.schema, textRow.key, text) }
    enabled: !page.saving
    onCommitted: function(next) { page.media.save(textRow.key, next) }
  }
}
