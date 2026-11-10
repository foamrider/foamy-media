const assert = require('node:assert/strict')
const B = require('../BrowserSetup.js')
const P = require('../Preferences.js')
const Prefs = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log() {}, warn() {} } })
const window = {appId:'vivaldi-youtube.com__-Default', title:'Example - YouTube'}
const players = [{dbusName:'org.mpris.MediaPlayer2.vivaldi.instance42', desktopEntry:'vivaldi-stable'}]
const entries = [{id:'vivaldi-stable', startupClass:'Vivaldi-stable', command:['/usr/bin/vivaldi-stable','%U']}]
const row = B.suggestion(window, players, entries)
assert.deepEqual(row.values, {youtubeAppId:window.appId, youtubeProfile:'Default', youtubeMprisName:'vivaldi', youtubeBrowser:'vivaldi-stable'})
assert.deepEqual(row.missing, [])
for (const [key,value] of Object.entries(row.values)) assert.equal(Prefs.valid(P.schema,key,value),true)
assert.equal(B.suggestion({appId:'vivaldi-stable',title:'Example - YouTube'},players,entries),null)
assert.equal(B.webApp('vivaldi-youtube.com.evil.test__-Default'),null)
assert.equal(B.webApp('vivaldi-music.youtube.com__-Default'),null)
assert.equal(B.webApp('vivaldi-youtube.com__-Bad\nProfile'),null)
assert.equal(B.suggestion({...window, appId:'vivaldi-youtube.com__-'+'a'.repeat(220)},players,entries),null)
const inactive = B.suggestion(window,[],entries)
assert.equal(inactive.values.youtubeMprisName,undefined)
assert.deepEqual(inactive.missing,['youtubeMprisName'])
assert.equal(inactive.values.youtubeBrowser,'vivaldi-stable')
const custom = B.suggestion({...window,appId:'vivaldi-youtube.com__-Profile_2'},players,entries)
assert.equal(custom.values.youtubeProfile,'Profile 2')
assert.equal(custom.inferredProfile,true)
const unknown=B.suggestion({...window,appId:'vivaldi-youtube.com__-Custom_Profile'},players,entries)
assert.equal(unknown.values.youtubeProfile,undefined)
assert.ok(unknown.missing.includes('youtubeProfile'))
assert.equal(B.suggestion(window,players,[{id:'vivaldi-stable',command:['flatpak','run','com.vivaldi.Vivaldi']}]).values.youtubeBrowser,undefined)
assert.equal(B.suggestion(window,players,[{id:'vivaldi-stable',command:['sh','-c','vivaldi']}]).values.youtubeBrowser,undefined)
assert.equal(B.suggestion(window,players,[{id:'vivaldi-stable',command:['other-program']}]).values.youtubeBrowser,undefined)
const ambiguousEntries = [{id:'vivaldi',command:['vivaldi']},{id:'vivaldi-stable',command:['vivaldi-stable']}]
assert.equal(B.suggestion(window,[],ambiguousEntries).values.youtubeBrowser,undefined)
assert.equal(B.suggestion(window,players,ambiguousEntries).values.youtubeBrowser,'vivaldi-stable')
assert.equal(B.candidates([window,window,{appId:'spotify',title:'Spotify'}],players,entries).length,1)
assert.deepEqual(B.candidates([],players,entries),[])
const chrome=B.suggestion({appId:'chrome-youtube.com__-Default',title:'YouTube'},
  [{dbusName:'org.mpris.MediaPlayer2.chrome.instance1',desktopEntry:'google-chrome'}],
  [{id:'google-chrome',startupClass:'Google-chrome',command:['google-chrome-stable']}])
assert.equal(chrome.values.youtubeBrowser,'google-chrome-stable')
assert.equal(chrome.values.youtubeMprisName,'chrome')
assert.equal(B.suggestion(window,[{dbusName:'org.mpris.MediaPlayer2.vivaldievil'}],entries).values.youtubeMprisName,undefined)
// BrowserPicker's summary reads the app ID through the schema: unset or
// invalid is the default app, the one the widget actually uses.
const selectedLabel = settings => B.description(Prefs.value(P.schema, settings, 'youtubeAppId'), Prefs.value(P.schema, settings, 'youtubeProfile'))
assert.equal(selectedLabel({}), 'Vivaldi · Default')
assert.equal(selectedLabel({youtubeAppId:'  ', youtubeProfile:'Default'}), 'Vivaldi · Default')
assert.equal(selectedLabel({youtubeAppId:'chromium-youtube.com__-Profile_2', youtubeProfile:'Profile 2'}), 'Chromium · Profile 2')
// Browser launch: only the tail of stderr is kept, whatever arrives.
const cap = B.LAUNCH_DIAGNOSTIC_CHARS
assert.equal(B.keepTail('', 'Error: Command not found: "nope"\n'), 'Error: Command not found: "nope"\n')
let tail = ''
for (let i = 0; i < 2000; i++) tail = B.keepTail(tail, 'x'.repeat(997) + i + '\n')
assert.equal(tail.length, cap)
assert.ok(tail.endsWith('1999\n'))
assert.equal(B.keepTail('kept', 'y'.repeat(cap * 3)), 'y'.repeat(cap))
assert.equal(B.keepTail('abc', 'def', 4), 'cdef')
assert.equal(B.keepTail(undefined, undefined), '')
assert.ok(B.LAUNCH_WINDOW_MS > 10000, 'the window outlasts uwsm-app giving up on its daemon')
// A failed launch: any non-zero exit or crash inside the window; never exit
// 0 (a hand-off to a running browser), never after the window.
assert.equal(B.launchFailed(0, false, false), false)
assert.equal(B.launchFailed(127, false, false), true)
assert.equal(B.launchFailed(9, true, false), true)
assert.equal(B.launchFailed(1, false, true), false)
assert.equal(B.launchFailed(15, true, true), false)
assert.equal(B.diagnostic('\x1b[31mError:\tbad\x07\nnext\r\n'), '[31mError: bad next')
assert.equal(B.diagnostic(''), '')
console.log('ok — browser setup detection, missing metadata, ambiguity, lookalike, and launch diagnostics tests passed')
