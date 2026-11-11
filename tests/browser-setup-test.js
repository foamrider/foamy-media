const assert = require('node:assert/strict')
const B = require('../BrowserSetup.js')
const P = require('../Preferences.js')
const Prefs = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log() {}, warn() {} } })
const window = {appId:'vivaldi-youtube.com__-Default', title:'Example - YouTube'}
const players = [{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance42', desktopEntry:'vivaldi-stable'}]
// YouTube is focus-only: a suggestion is the window to focus and the player
// to control, never a browser or profile to start.
const row = B.suggestion(window, players)
assert.deepEqual(row.values, {youtubeAppId:window.appId, youtubeMprisName:'vivaldi'})
assert.deepEqual(row.missing, [])
for (const [key,value] of Object.entries(row.values)) assert.equal(Prefs.valid(P.schema,key,value),true)
for (const appId of ['vivaldi-youtube.com__-Default', 'chromium-youtube.com__-Profile_2', 'vivaldi-youtube.com__-Custom_Profile']) {
  const suggested = B.suggestion({...window, appId}, players.concat([{dbusName:'org.mpris.MediaPlayer2.chromium.instance7'}]))
  assert.deepEqual(Object.keys(suggested.values).sort(), ['youtubeAppId', 'youtubeMprisName'], appId)
  for (const key of Object.keys(suggested.values)) assert.ok(Prefs.field(P.schema, key), 'suggested key is a setting: ' + key)
}
assert.equal(B.suggestion({appId:'vivaldi-stable',title:'Example - YouTube'},players),null)
assert.equal(B.webApp('vivaldi-youtube.com.evil.test__-Default'),null)
assert.equal(B.webApp('vivaldi-music.youtube.com__-Default'),null)
assert.equal(B.webApp('vivaldi-youtube.com__-Bad\nProfile'),null)
assert.equal(B.suggestion({...window, appId:'vivaldi-youtube.com__-'+'a'.repeat(220)},players),null)
const inactive = B.suggestion(window,[])
assert.deepEqual(inactive.values,{youtubeAppId:window.appId})
assert.deepEqual(inactive.missing,['youtubeMprisName'])
assert.deepEqual(B.suggestion(window,undefined).values,{youtubeAppId:window.appId})
// Two players of the browser's family: ambiguous, so the MPRIS name is left unset.
assert.equal(B.suggestion(window,[{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance1'},{dbusName:'org.mpris.MediaPlayer2.vivaldi-stable.instance2'}]).values.youtubeMprisName,undefined)
assert.equal(B.suggestion(window,[{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance1'},{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance2'}]).values.youtubeMprisName,'vivaldi')
assert.equal(B.candidates([window,window,{appId:'spotify',title:'Spotify'}],players).length,1)
assert.deepEqual(B.candidates([],players),[])
const chrome=B.suggestion({appId:'chrome-youtube.com__-Default',title:'YouTube'},
  [{dbusName:'org.mpris.MediaPlayer2.chrome.instance1',desktopEntry:'google-chrome'}])
assert.deepEqual(chrome.values,{youtubeAppId:'chrome-youtube.com__-Default',youtubeMprisName:'chrome'})
assert.equal(B.suggestion(window,[{dbusName:'org.mpris.MediaPlayer2.vivaldievil'}]).values.youtubeMprisName,undefined)
// BrowserPicker's summary reads the app ID through the schema: unset or
// invalid is the default app, the one the widget actually uses. The profile
// comes from the app ID (Chromium's Profile_N shown as its directory name).
const selectedLabel = settings => B.description(Prefs.value(P.schema, settings, 'youtubeAppId'))
assert.equal(selectedLabel({}), 'Vivaldi · Default')
assert.equal(selectedLabel({youtubeAppId:'  '}), 'Vivaldi · Default')
assert.equal(selectedLabel({youtubeAppId:'chromium-youtube.com__-Profile_2'}), 'Chromium · Profile 2')
assert.equal(selectedLabel({youtubeAppId:'vivaldi-youtube.com__-Custom_Profile'}), 'Vivaldi · Custom_Profile')
// A legacy entry's browser and profile don't change the summary.
assert.equal(selectedLabel({youtubeAppId:'chromium-youtube.com__-Default', youtubeBrowser:'chromium', youtubeProfile:'Profile 9'}), 'Chromium · Default')
assert.equal(B.description('not-a-web-app'), '')
// The launch helpers are gone with the browser start.
for (const name of ['LAUNCH_WINDOW_MS', 'LAUNCH_DIAGNOSTIC_CHARS', 'keepTail', 'launchFailed', 'diagnostic'])
  assert.equal(B[name], undefined, name)
// Panel: launch() only ever focuses the YouTube window or runs Omarchy's
// Spotify launcher; no plugin QML builds a process to start a browser.
const fs = require('node:fs'), path = require('node:path')
const root = path.join(__dirname, '..')
const panel = fs.readFileSync(path.join(root, 'Panel.qml'), 'utf8')
const launch = /\n  function launch\(\) \{\n([\s\S]*?)\n  \}\n/.exec(panel)
assert.ok(launch, 'Panel.launch()')
assert.deepEqual([...launch[1].matchAll(/bar\.run\(([^)]*)\)/g)].map(m => m[1]), ['"omarchy launch spotify"'])
assert.ok(/youtubeWindow\.activate\(\)/.test(launch[1]), 'YouTube is focused')
for (const file of fs.readdirSync(root).filter(f => /\.(qml|js)$/.test(f))) {
  const text = fs.readFileSync(path.join(root, file), 'utf8')
  for (const banned of ['uwsm-app', '--app=', '--profile-directory', 'startBrowser', 'youtubeLaunch'])
    assert.ok(!text.includes(banned), file + ' mentions ' + banned)
}
assert.ok(!/\bProcess\s*\{|createObject|Quickshell\.Io/.test(panel), 'Panel.qml creates no process')
console.log('ok — browser setup detection (app ID and MPRIS name only), missing metadata, ambiguity and lookalike tests passed')
