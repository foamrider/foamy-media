const assert = require('node:assert/strict')
const test = require('node:test')
const B = require('../BrowserSetup.js')
const P = require('../Preferences.js')
const Prefs = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log() {}, warn() {} } })
const window = {appId:'vivaldi-youtube.com__-Default', title:'Example - YouTube'}
const players = [{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance42', desktopEntry:'vivaldi-stable'}]

test('a suggestion is the window to focus and the player to control', () => {
  // YouTube is focus-only: never a browser or profile to start.
  const row = B.suggestion(window, players)
  assert.deepEqual(row.values, {youtubeAppId:window.appId, youtubeMprisName:'vivaldi'})
  assert.deepEqual(row.missing, [])
  for (const [key,value] of Object.entries(row.values)) assert.equal(Prefs.valid(P.schema,key,value),true)
  // Each window takes the player of its own browser family.
  const both = players.concat([{dbusName:'org.mpris.MediaPlayer2.chromium.instance7'}])
  for (const [appId, name] of [['vivaldi-youtube.com__-Default', 'vivaldi'], ['chromium-youtube.com__-Profile_2', 'chromium'],
    ['vivaldi-youtube.com__-Custom_Profile', 'vivaldi']])
    assert.deepEqual(B.suggestion({...window, appId}, both).values, {youtubeAppId:appId, youtubeMprisName:name}, appId)
})

test('windows that are not a YouTube web app, or with unsafe names, give no suggestion', () => {
  assert.equal(B.suggestion({appId:'vivaldi-stable',title:'Example - YouTube'},players),null)
  assert.equal(B.webApp('vivaldi-youtube.com.evil.test__-Default'),null)
  assert.equal(B.webApp('vivaldi-music.youtube.com__-Default'),null)
  assert.equal(B.webApp('vivaldi-youtube.com__-Bad\nProfile'),null)
  assert.equal(B.suggestion({...window, appId:'vivaldi-youtube.com__-'+'a'.repeat(220)},players),null)
})

test('the MPRIS name is left unset when no player or more than one could own the window', () => {
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
})

test('a Chrome-named web-app window takes the chromium player', () => {
  // Chromium (Omarchy's default browser) names a web-app window like Chrome
  // does ("chrome-…", omarchy-webapp-window-class) but plays as "chromium".
  const chromiumWindow = {appId:'chrome-youtube.com__-Default', title:'YouTube'}
  const chromium = B.suggestion(chromiumWindow, [{dbusName:'org.mpris.MediaPlayer2.chromium.instance4242'}])
  assert.deepEqual(chromium.values, {youtubeAppId:'chrome-youtube.com__-Default', youtubeMprisName:'chromium'})
  assert.deepEqual(chromium.missing, [])
  // Chrome and Chromium playing at once: either could own the window, so no guess.
  const both = B.suggestion(chromiumWindow, [{dbusName:'org.mpris.MediaPlayer2.chromium.instance1'},
    {dbusName:'org.mpris.MediaPlayer2.chrome.instance2'}])
  assert.equal(both.values.youtubeMprisName, undefined)
  assert.deepEqual(both.missing, ['youtubeMprisName'])
  // The widening is chrome's alone: a chromium-named window does not take a Chrome player.
  assert.equal(B.suggestion({appId:'chromium-youtube.com__-Default', title:'YouTube'},
    [{dbusName:'org.mpris.MediaPlayer2.chrome.instance1'}]).values.youtubeMprisName, undefined)
})

test("Omarchy's hint counts only as one line naming a Chromium YouTube web app", () => {
  // Junk, failure output and other browsers give no hint.
  assert.equal(B.omarchyAppId('chrome-youtube.com__-Default\n'), 'chrome-youtube.com__-Default')
  assert.equal(B.omarchyAppId('chrome-youtube.com__-Default'), 'chrome-youtube.com__-Default')
  for (const junk of ['', '\n', 'chrome-youtube.com__-Default\nsecond line\n', 'vivaldi-youtube.com__-Default\n',
    'chrome-music.youtube.com__-Default\n', 'chrome-youtube.com__-' + 'x'.repeat(200), 'x'.repeat(512),
    'Usage: omarchy-webapp-window-class <url>\n', 'chrome-youtube.com__-De\u0000fault', undefined, null])
    assert.equal(B.omarchyAppId(junk), '', JSON.stringify(junk))
  // The hinted window comes first and is marked; nothing is marked without a hint.
  const hintWindows = [{appId:'vivaldi-youtube.com__-Default', title:'A - YouTube'},
    {appId:'chrome-youtube.com__-Default', title:'B - YouTube'}]
  const hintPlayers = [{dbusName:'org.mpris.MediaPlayer2.chromium.instance9'}]
  const hinted = B.candidates(hintWindows, hintPlayers, 'chrome-youtube.com__-Default')
  assert.deepEqual(hinted.map(r => [r.id, r.hinted]), [['chrome-youtube.com__-Default', true], ['vivaldi-youtube.com__-Default', false]])
  assert.deepEqual(hinted[0].values, {youtubeAppId:'chrome-youtube.com__-Default', youtubeMprisName:'chromium'})
  for (const hint of [undefined, '', 'chrome-youtube.com__-Profile_1']) {
    const rows = B.candidates(hintWindows, hintPlayers, hint)
    assert.deepEqual(rows.map(r => [r.id, r.hinted]), [['vivaldi-youtube.com__-Default', false], ['chrome-youtube.com__-Default', false]], String(hint))
  }
  // The defaults stay Vivaldi's: the hint never changes them.
  const manifestDefaults = require('../manifest.json').barWidget.defaults
  assert.equal(manifestDefaults.youtubeAppId, 'vivaldi-youtube.com__-Default')
  assert.equal(manifestDefaults.youtubeMprisName, 'vivaldi')
})

test("the picker's summary names the app the widget uses", () => {
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
})
