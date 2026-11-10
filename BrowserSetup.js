// Browser setup suggestions use live windows, MPRIS names and desktop entries.
// Unknown or ambiguous values stay unset so existing settings are not guessed over.
function family(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "")
    .replace(/^(google-|org\.)/, "").replace(/-(stable|browser)$/, "")
}
function webApp(appId) {
  var match = /^([A-Za-z0-9._+-]+)-youtube\.com__-(.+)$/.exec(String(appId || ""))
  if (!match || /[\x00-\x1f\x7f]/.test(match[2])) return null
  return {browser:match[1], profile:match[2]}
}
// A readable profile summary replaces raw app IDs in the window picker.
function description(appId, profile) {
  var app = webApp(appId)
  if (!app) return ""
  var browser = family(app.browser)
  return browser.charAt(0).toUpperCase() + browser.slice(1) + " · " + (profile || app.profile)
}
function unique(values) {
  var result = []
  for (var i = 0; i < values.length; i++)
    if (values[i] && result.indexOf(values[i]) === -1) result.push(values[i])
  return result
}
function executable(entry) {
  var command = entry && entry.command || []
  if (!command.length) return ""
  var name = String(command[0]).split("/").pop()
  // Launch wrappers may carry necessary arguments, which the browser field cannot represent.
  if (["env", "flatpak", "sh", "bash", "uwsm", "uwsm-app"].indexOf(name) !== -1) return ""
  return /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(name) ? name : ""
}
function suggestion(window, players, entries) {
  var appId = String(window && window.appId || "")
  var app = webApp(appId)
  if (!app || appId.length > 200) return null
  var patch = {youtubeAppId:appId}
  // Chromium uses Profile N directories, but sanitises their spaces in app IDs.
  // Mark that inference for review; arbitrary suffixes cannot be reversed safely.
  if (app.profile === "Default" || /^Profile [0-9]+$/.test(app.profile)) patch.youtubeProfile = app.profile
  var inferredProfile = /^Profile_[0-9]+$/.test(app.profile)
  if (inferredProfile) patch.youtubeProfile = app.profile.replace("_", " ")
  var browserFamily = family(app.browser)
  var names = [], desktopIds = []
  for (var i = 0; i < players.length; i++) {
    var player = players[i]
    var match = /^org\.mpris\.MediaPlayer2\.([A-Za-z0-9_+-]+)(?:\.|$)/i.exec(String(player.dbusName || ""))
    if (!match || family(match[1]) !== browserFamily) continue
    names.push(match[1])
    if (player.desktopEntry) desktopIds.push(String(player.desktopEntry).replace(/\.desktop$/, ""))
  }
  names = unique(names)
  if (names.length === 1) patch.youtubeMprisName = names[0]
  var exactCommands = [], familyCommands = []
  for (var j = 0; j < entries.length; j++) {
    var entry = entries[j]
    var id = String(entry.id || "").replace(/\.desktop$/, "")
    var command = executable(entry)
    // Exclude app launchers and unrelated commands, even if their labels resemble the browser.
    if (!command || family(command) !== browserFamily) continue
    if (desktopIds.indexOf(id) !== -1) exactCommands.push(command)
    if (family(id) === browserFamily || family(entry.startupClass) === browserFamily) familyCommands.push(command)
  }
  var commands = unique(exactCommands.length ? exactCommands : familyCommands)
  if (commands.length === 1) patch.youtubeBrowser = commands[0]
  var missing = ["youtubeBrowser", "youtubeProfile", "youtubeMprisName"].filter(function(key) { return !patch[key] })
  return {id:appId, title:String(window.title || "YouTube"), values:patch, missing:missing, inferredProfile:inferredProfile}
}
function candidates(windows, players, entries) {
  var result = [], seen = []
  for (var i = 0; i < windows.length; i++) {
    var row = suggestion(windows[i], players, entries)
    if (!row || seen.indexOf(row.id) !== -1) continue
    seen.push(row.id)
    result.push(row)
  }
  return result.sort(function(a,b) { return a.title.localeCompare(b.title) || a.id.localeCompare(b.id) })
}
// Launching the browser. uwsm-app execs it in place, so the browser can stay
// the launch's own child for hours, writing to its stderr all the while. A
// launch that fails does so quickly (uwsm-app gives up on its daemon after
// 10 s); only within that window is stderr kept, and only its tail.
var LAUNCH_WINDOW_MS = 15000
var LAUNCH_DIAGNOSTIC_CHARS = 4096
function keepTail(buffer, chunk, limit) {
  var max = limit > 0 ? limit : LAUNCH_DIAGNOSTIC_CHARS
  var next = String(chunk || "")
  if (next.length >= max) return next.slice(next.length - max)
  var text = String(buffer || "") + next
  return text.length > max ? text.slice(text.length - max) : text
}
// Exiting 0 is a browser handing the window to its running instance. Any
// other exit or a crash counts only while the launch can still fail: a
// browser that ran past the window and closes later is not a failed launch.
function launchFailed(exitCode, crashed, settled) {
  return !settled && (crashed === true || exitCode !== 0)
}
// The kept tail as one log line: control characters (escape sequences
// included) become spaces.
function diagnostic(text) {
  return String(text || "").replace(/[\x00-\x1f\x7f]+/g, " ").trim()
}
if (typeof module !== "undefined") module.exports = {description:description, webApp:webApp, suggestion:suggestion, candidates:candidates,
  LAUNCH_WINDOW_MS:LAUNCH_WINDOW_MS, LAUNCH_DIAGNOSTIC_CHARS:LAUNCH_DIAGNOSTIC_CHARS, keepTail:keepTail, launchFailed:launchFailed, diagnostic:diagnostic}
