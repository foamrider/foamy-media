// Settings schema for the media widget: `fields` mirrors manifest.json
// barWidget.schema; validation and saving are foamy-kit FoamyPrefs.js.
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
// Short labels for the settings page (the manifest labels are for the bar editor).
var labels = {
  "leftClick": "Left-click plays/pauses",
  "hideWhenClosed": "Hide when stopped",
  "scrollAction": "Mouse wheel",
  "volumeStep": "Volume step (%)",
  "maxLabelWidth": "Label width (px)",
  "showArtist": "Show the artist in the bar",
  "showProgress": "Show progress in the bar",
  "animateTitle": "Scroll long titles",
  "showEqualizer": "Show the equalizer",
  "accent": "Accent",
  "artBackground": "Artwork background",
  "artIntensity": "Artwork intensity (%)",
  "youtubeEnabled": "Enable YouTube",
  "youtubeBrowser": "Browser",
  "youtubeProfile": "Profile",
  "youtubeAppId": "Window app ID",
  "youtubeMprisName": "MPRIS name"
}

// Extra constraints for foamy-kit's FoamyPrefs engine. The browser value is
// launched (uwsm-app -- <browser>), so it and the MPRIS name are bare program
// names that cannot start with "-"; profiles and app IDs are any non-blank
// single line. Kept out of `fields`, which mirrors manifest.json exactly.
var namePattern = "^[A-Za-z0-9][A-Za-z0-9._+-]*$"
var linePattern = "^(?=.*\\S)[^\\x00-\\x1f\\x7f]+$"
var constraints = {
  "youtubeBrowser": { pattern: namePattern, maxLength: 200 },
  "youtubeMprisName": { pattern: namePattern, maxLength: 200 },
  "youtubeProfile": { pattern: linePattern, maxLength: 200 },
  "youtubeAppId": { pattern: linePattern, maxLength: 200 }
}
// The schema handed to FoamyPrefs (validation, defaults, saving).
var schema = fields.map(function(field) {
  var extra = constraints[field.key]
  if (!extra) return field
  var out = {}
  for (var key in field) out[key] = field[key]
  for (var name in extra) out[name] = extra[name]
  return out
})

function clickAction(button, leftClick) {
  if (button === "middle") return "next"
  if (button !== "left" && button !== "right") return "none"
  return (button === "left") === (leftClick !== "Play/pause") ? "panel" : "playPause"
}
// The validated browser and profile (Prefs.value) launch the dedicated web app.
function youtubeLaunch(browser, profile) {
  return ["uwsm-app", "--", String(browser), "--app=https://youtube.com/", "--profile-directory=" + String(profile)]
}
if (typeof module !== "undefined") module.exports = {labels: labels, fields: fields, schema: schema,
  constraints: constraints, clickAction: clickAction, youtubeLaunch: youtubeLaunch}
