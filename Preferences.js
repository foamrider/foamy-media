// Shared settings validation and English/Norwegian labels.
var fields = [
  {
    "key": "maxLabelWidth",
    "type": "integer",
    "label": "Maximum label width (px)",
    "min": 60,
    "max": 600,
    "step": 10,
    "defaultValue": 200,
    "description": "Track text wider than this scrolls instead of stretching the bar."
  },
  {
    "key": "showArtist",
    "type": "boolean",
    "label": "Show artist next to the title",
    "defaultValue": true
  },
  {
    "key": "showProgress",
    "type": "boolean",
    "label": "Show a progress underline in the bar",
    "defaultValue": true
  },
  {
    "key": "hideWhenClosed",
    "type": "boolean",
    "label": "Hide when playback stops",
    "defaultValue": true,
    "description": "Paused tracks remain visible. Turn off to keep a dimmed source icon when supported players are stopped, empty, or closed."
  },
  {
    "key": "leftClick",
    "type": "enum",
    "label": "Left click",
    "options": [
      "Open panel",
      "Play/pause"
    ],
    "defaultValue": "Open panel",
    "description": "Which action left click takes. The other of the two lands on right click."
  },
  {
    "key": "scrollAction",
    "type": "enum",
    "label": "Mouse wheel over the widget",
    "options": [
      "Previous/next track",
      "Volume",
      "Nothing"
    ],
    "defaultValue": "Previous/next track"
  },
  {
    "key": "accent",
    "type": "enum",
    "label": "Accent color",
    "options": [
      "Source color",
      "Album art",
      "Theme accent",
      "Bar foreground"
    ],
    "defaultValue": "Source color",
    "description": "Color of the icon, progress underline, and popup controls. Source color is Spotify green or YouTube red; Album art takes the dominant color of the current artwork."
  },
  {
    "key": "artBackground",
    "type": "boolean",
    "label": "Album cover behind the panel",
    "defaultValue": true,
    "description": "Blurs the current cover into the panel background, tinted and dimmed to whatever keeps the theme's text readable. Needs ImageMagick and curl for the color reading; without them the panel keeps its plain background."
  },
  {
    "key": "artIntensity",
    "type": "integer",
    "label": "How much cover shows through (%)",
    "min": 0,
    "max": 100,
    "step": 5,
    "defaultValue": 55,
    "description": "A starting point, not a fixed opacity — bright covers are still covered more heavily than dark ones from wherever this is set."
  },
  {
    "key": "language",
    "type": "enum",
    "label": "Language",
    "options": [
      "system",
      "nb",
      "en"
    ],
    "defaultValue": "system"
  },
  {
    "key": "animateTitle",
    "type": "boolean",
    "label": "Animate track title",
    "defaultValue": true
  },
  {
    "key": "showEqualizer",
    "type": "boolean",
    "label": "Show animated equalizer",
    "defaultValue": true
  },
  {
    "key": "volumeStep",
    "type": "integer",
    "label": "Volume scroll step (%)",
    "min": 1,
    "max": 20,
    "step": 1,
    "defaultValue": 5
  },
  {
    "key": "youtubeEnabled",
    "type": "boolean",
    "label": "Enable YouTube integration",
    "defaultValue": true
  },
  {
    "key": "youtubeBrowser",
    "type": "string",
    "label": "Browser executable",
    "defaultValue": "vivaldi"
  },
  {
    "key": "youtubeProfile",
    "type": "string",
    "label": "Browser profile",
    "defaultValue": "Default"
  },
  {
    "key": "youtubeAppId",
    "type": "string",
    "label": "YouTube window app ID",
    "defaultValue": "vivaldi-youtube.com__-Default"
  },
  {
    "key": "youtubeMprisName",
    "type": "string",
    "label": "MPRIS browser name",
    "defaultValue": "vivaldi"
  }
]
var norwegian = {
  "Could not start browser.": "Kunne ikke starte nettleseren.",
  "Settings": "Innstillinger",
  "Back": "Tilbake",
  "Language": "Språk",
  "Default (system language)": "Standard (systemspråk)",
  "Controls": "Kontroller",
  "Appearance": "Utseende",
  "YouTube integration": "YouTube-integrasjon",
  "Left-click plays/pauses": "Venstreklikk spiller av / setter på pause",
  "Right-click opens the popup.": "Høyreklikk åpner panelet.",
  "Left-click opens the popup.": "Venstreklikk åpner panelet.",
  "Maximum label width (px)": "Maksimal tekstbredde (px)",
  "Show artist next to the title": "Vis artist ved siden av tittelen",
  "Show a progress underline in the bar": "Vis fremdriftslinje i linjen",
  "Hide when playback stops": "Skjul når avspillingen stopper",
  "Mouse wheel over the widget": "Musehjul over modulen",
  "Previous/next track": "Forrige/neste spor",
  "Volume": "Volum",
  "Nothing": "Ingen handling",
  "Accent color": "Aksentfarge",
  "Source color": "Kildefarge",
  "Album art": "Albumomslag",
  "Theme accent": "Temaets aksentfarge",
  "Bar foreground": "Linjens tekstfarge",
  "Album cover behind the panel": "Albumomslag bak panelet",
  "How much cover shows through (%)": "Synlighet for albumomslag (%)",
  "Animate track title": "Animer sportittel",
  "Show animated equalizer": "Vis animert lydindikator",
  "Volume scroll step (%)": "Volumsteg med musehjul (%)",
  "Enable YouTube integration": "Aktiver YouTube-integrasjon",
  "Browser executable": "Nettleserprogram",
  "Browser profile": "Nettleserprofil",
  "YouTube window app ID": "App-ID for YouTube-vindu",
  "MPRIS browser name": "Nettlesernavn i MPRIS",
  "These identifiers must match the dedicated YouTube web app and its browser.": "Identifikatorene må samsvare med YouTube-nettappen og nettleseren.",
  "Settings are saved automatically.": "Innstillingene lagres automatisk.",
  "Saving…": "Lagrer…",
  "Could not save settings.": "Kunne ikke lagre innstillingene.",
  "Invalid setting.": "Ugyldig innstilling.",
  "Nothing playing": "Ingenting spilles",
  "Not running": "Ikke startet",
  "Shuffle on": "Tilfeldig rekkefølge på",
  "Shuffle off": "Tilfeldig rekkefølge av",
  "Previous track": "Forrige spor",
  "Next track": "Neste spor",
  "Play": "Spill av",
  "Pause": "Pause",
  "Repeat: track": "Gjenta: spor",
  "Repeat: playlist": "Gjenta: spilleliste",
  "Repeat: off": "Gjenta: av",
  "Show": "Vis",
  "Start": "Start",
  "Paused": "På pause",
  "Open panel": "Åpne panel",
  "Play/pause": "Spill av / pause"
}

function language(mode, locale) {
  if (mode === "en" || mode === "nb") return mode
  return /^(nb|nn|no)(_|-|$)/i.test(String(locale || "")) ? "nb" : "en"
}
function text(value, lang) { return lang === "nb" ? (norwegian[value] || value) : value }
function field(key) {
  for (var i = 0; i < fields.length; i++) if (fields[i].key === key) return fields[i]
  return null
}
function valid(key, value) {
  var spec = field(key)
  if (!spec) return false
  if (spec.type === "boolean") return typeof value === "boolean"
  if (spec.type === "integer") return typeof value === "number" && isFinite(value)
    && Math.floor(value) === value && value >= spec.min && value <= spec.max
  if (spec.type === "enum") return spec.options.indexOf(value) !== -1
  if (typeof value !== "string" || !value.trim() || value.length > 200 || /[\x00-\x1f\x7f]/.test(value)) return false
  if (key === "youtubeBrowser" || key === "youtubeMprisName") return /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value)
  return true
}
function value(settings, key) {
  var spec = field(key)
  if (!spec) return undefined
  return settings && valid(key, settings[key]) ? settings[key] : spec.defaultValue
}
function clickAction(button, leftClick) {
  if (button === "middle") return "next"
  if (button !== "left" && button !== "right") return "none"
  return (button === "left") === (leftClick !== "Play/pause") ? "panel" : "playPause"
}
function youtubeLaunch(settings) {
  return ["uwsm-app", "--", value(settings, "youtubeBrowser"),
    "--app=https://youtube.com/", "--profile-directory=" + value(settings, "youtubeProfile")]
}
if (typeof module !== "undefined") module.exports = {fields: fields, norwegian: norwegian, language: language,
  text: text, field: field, valid: valid, value: value, clickAction: clickAction, youtubeLaunch: youtubeLaunch}
