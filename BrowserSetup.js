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
  var browserFamily = family(app.browser)
  var names = []
  for (var i = 0; i < (players || []).length; i++) {
    var match = /^org\.mpris\.MediaPlayer2\.([A-Za-z0-9_+-]+)(?:\.|$)/i.exec(String(players[i].dbusName || ""))
    if (match && family(match[1]) === browserFamily) names.push(match[1])
  }
  names = unique(names)
  if (names.length === 1) patch.youtubeMprisName = names[0]
  var missing = patch.youtubeMprisName ? [] : ["youtubeMprisName"]
  return {id:appId, title:String(window.title || "YouTube"), values:patch, missing:missing}
}
function candidates(windows, players) {
  var result = [], seen = []
  for (var i = 0; i < windows.length; i++) {
    var row = suggestion(windows[i], players)
    if (!row || seen.indexOf(row.id) !== -1) continue
    seen.push(row.id)
    result.push(row)
  }
  return result.sort(function(a,b) { return a.title.localeCompare(b.title) || a.id.localeCompare(b.id) })
}
if (typeof module !== "undefined") module.exports = {description:description, webApp:webApp, suggestion:suggestion, candidates:candidates}
