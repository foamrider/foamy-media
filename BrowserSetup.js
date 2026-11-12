// Browser setup suggestions use live windows and MPRIS names. The plugin only
// matches and focuses the YouTube web app (it never starts a browser), so a
// suggestion is the window's app ID and the MPRIS name its browser plays
// under. An unknown or ambiguous name stays unset so an existing setting is
// not guessed over.
function family(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "")
    .replace(/^(google-|org\.)/, "").replace(/-(stable|browser)$/, "")
}
function webApp(appId) {
  var match = /^([A-Za-z0-9._+-]+)-youtube\.com__-(.+)$/.exec(String(appId || ""))
  if (!match || /[\x00-\x1f\x7f]/.test(match[2])) return null
  return {browser:match[1], profile:match[2]}
}
// A readable browser and profile summary replaces raw app IDs in the window
// picker. Chromium sanitises the space of its "Profile N" directories to
// "Profile_N" in app IDs; that one form is shown as the directory name.
function description(appId) {
  var app = webApp(appId)
  if (!app) return ""
  var browser = family(app.browser)
  var profile = /^Profile_[0-9]+$/.test(app.profile) ? app.profile.replace("_", " ") : app.profile
  return browser.charAt(0).toUpperCase() + browser.slice(1) + " · " + profile
}
// The MPRIS name families a web-app window's browser can play under.
// Chromium and Google Chrome both name the window "chrome-<host>__-<profile>"
// (Omarchy's omarchy-webapp-window-class prints that form), but Chromium
// publishes MPRIS as "chromium" and Chrome as "chrome", so a chrome window
// matches either. Both running at once stays ambiguous (suggestion()).
function playerFamilies(browserFamily) {
  return browserFamily === "chrome" ? ["chrome", "chromium"] : [browserFamily]
}
function unique(values) {
  var result = []
  for (var i = 0; i < values.length; i++)
    if (values[i] && result.indexOf(values[i]) === -1) result.push(values[i])
  return result
}
function suggestion(window, players) {
  var appId = String(window && window.appId || "")
  var app = webApp(appId)
  if (!app || appId.length > 200) return null
  var patch = {youtubeAppId:appId}
  var families = playerFamilies(family(app.browser))
  var names = []
  for (var i = 0; i < (players || []).length; i++) {
    var match = /^org\.mpris\.MediaPlayer2\.([A-Za-z0-9_+-]+)(?:\.|$)/i.exec(String(players[i].dbusName || ""))
    if (match && families.indexOf(family(match[1])) !== -1) names.push(match[1])
  }
  names = unique(names)
  if (names.length === 1) patch.youtubeMprisName = names[0]
  var missing = patch.youtubeMprisName ? [] : ["youtubeMprisName"]
  return {id:appId, title:String(window.title || "YouTube"), values:patch, missing:missing}
}
// The app ID in what `omarchy-webapp-window-class https://youtube.com/`
// printed (at most 512 bytes; Panel bounds the read), or "". Only one line
// naming a Chromium YouTube web app ("chrome-youtube.com__-Default") counts:
// anything else, an empty or partial answer included, gives no hint.
function omarchyAppId(text) {
  var value = String(text === undefined || text === null ? "" : text).replace(/\n$/, "")
  if (value.length > 200 || /[\x00-\x1f\x7f]/.test(value)) return ""
  var app = webApp(value)
  return app && family(app.browser) === "chrome" ? value : ""
}
// The window rows, by title. `hint` is the app ID of Omarchy's YouTube web
// app (Panel passes it only while it applies): its row comes first and is
// marked `hinted`, so one click on it sets that window.
function candidates(windows, players, hint) {
  var result = [], seen = []
  for (var i = 0; i < windows.length; i++) {
    var row = suggestion(windows[i], players)
    if (!row || seen.indexOf(row.id) !== -1) continue
    seen.push(row.id)
    row.hinted = !!hint && row.id === hint
    result.push(row)
  }
  return result.sort(function(a,b) {
    return Number(b.hinted) - Number(a.hinted) || a.title.localeCompare(b.title) || a.id.localeCompare(b.id)
  })
}
if (typeof module !== "undefined") module.exports = {description:description, webApp:webApp, suggestion:suggestion, candidates:candidates, omarchyAppId:omarchyAppId}
