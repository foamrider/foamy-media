const I18n = require('./i18n.cjs')
const assert = require('node:assert/strict')
const P = require('../Preferences.js')
const Prefs = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log() {}, warn() {} } })
const M = require('../Model.js')
const manifest = require('../manifest.json')
const S = P.schema
assert.deepEqual(P.fields, manifest.barWidget.schema)
for (const f of P.fields) {
  assert.equal(Prefs.valid(S, f.key, f.defaultValue), true, f.key)
  assert.equal(Prefs.value(S, {}, f.key), manifest.barWidget.defaults[f.key])
  assert.equal(Prefs.valid(S, f.key, null), false)
  assert.ok(I18n.no[f.label] || f.key === 'leftClick', f.label)
  assert.ok(P.labels[f.key], 'settings label for ' + f.key)
  assert.ok(I18n.no[P.labels[f.key]], 'translated settings label for ' + f.key)
  for (const option of f.options || []) assert.ok(I18n.no[option], 'translated option ' + option)
}
assert.equal(Prefs.valid(S, 'language', 'de'), false)
for (const value of [-1, 0, 21, NaN, Infinity, '5', 1.5]) assert.equal(Prefs.valid(S, 'volumeStep', value), false)
for (const value of [1, 5, 20]) assert.equal(Prefs.valid(S, 'volumeStep', value), true)
assert.equal(Prefs.valid(S, 'showArtist', 'false'), false)
assert.equal(Prefs.valid(S, 'unknown', true), false)
assert.equal(Prefs.value(S, { volumeStep: -5 }, 'volumeStep'), 5)
// The MPRIS name is a bare name; the app ID any non-blank single line.
for (const value of ['--help', '-x', 'vivaldi;echo', '$(echo bad)', 'browser\nname', '', ' ', '/usr/bin/vivaldi', 'a'.repeat(201)])
  assert.equal(Prefs.valid(S, 'youtubeMprisName', value), false, JSON.stringify(value))
for (const value of ['', '   ', 'app\nid', 'x\u007f', 'a'.repeat(201)])
  assert.equal(Prefs.valid(S, 'youtubeAppId', value), false, JSON.stringify(value))
assert.equal(Prefs.valid(S, 'youtubeAppId', 'vivaldi-youtube.com__-Default'), true)
assert.equal(Prefs.valid(S, 'youtubeMprisName', 'chromium'), true)
// The schema keeps the manifest fields untouched.
assert.equal(P.fields.find(f => f.key === 'youtubeMprisName').pattern, undefined)
// YouTube is focus-only: no browser or profile setting, and nothing builds a
// browser command.
for (const key of ['youtubeBrowser', 'youtubeProfile']) {
  assert.equal(Prefs.field(S, key), null, key)
  assert.equal(key in manifest.barWidget.defaults, false, key)
  assert.equal(P.labels[key], undefined, key)
  assert.equal(P.constraints[key], undefined, key)
  assert.equal(Prefs.valid(S, key, 'vivaldi'), false, key)
}
assert.equal(P.youtubeLaunch, undefined)
// A saved entry from 1.3.3 or earlier still holds youtubeBrowser and
// youtubeProfile: it reads cleanly (every setting its saved or default value,
// the legacy keys not among them, nothing logged) and a later save keeps
// them untouched rather than failing or dropping the entry's other keys.
const logged = []
const quiet = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log: (...a) => logged.push(a), warn: (...a) => logged.push(a), error: (...a) => logged.push(a) } })
const legacy = { id: 'foamy.media', youtubeEnabled: true, youtubeBrowser: 'chromium', youtubeProfile: 'Profile 2',
  youtubeAppId: 'chromium-youtube.com__-Profile_2', youtubeMprisName: 'chromium', showArtist: false }
const read = quiet.values(S, legacy)
assert.deepEqual(Object.keys(read).sort(), P.fields.map(f => f.key).sort())
assert.equal(read.youtubeAppId, 'chromium-youtube.com__-Profile_2')
assert.equal(read.youtubeMprisName, 'chromium')
assert.equal(read.showArtist, false)
assert.equal(read.volumeStep, 5)
assert.equal(quiet.value(S, legacy, 'youtubeBrowser'), undefined)
const legacySaved = []
const legacyBar = { shell: { updateEntryInline(id, settings) { legacySaved.push(settings); return true } } }
const legacyResult = quiet.save(legacyBar, 'foamy.media', S, legacy, 'youtubeMprisName', 'vivaldi')
assert.equal(legacyResult.ok && legacyResult.inline, true)
assert.equal(legacySaved[0].youtubeMprisName, 'vivaldi')
assert.equal(legacySaved[0].youtubeBrowser, 'chromium')
assert.equal(legacySaved[0].youtubeProfile, 'Profile 2')
assert.equal(legacySaved[0].showArtist, false)
assert.deepEqual(logged, [])
// Saving: inline through the bar with the merged entry, else the omarchy CLI.
const saved = []
const bar = { shell: { updateEntryInline(id, settings) { saved.push({ id, settings }); return true } } }
let result = Prefs.save(bar, 'foamy.media', S, { id: 'foamy.media', showArtist: true, extra: 1 }, 'showArtist', false)
assert.equal(result.ok && result.inline, true)
assert.equal(JSON.stringify(saved[0]), JSON.stringify({ id: 'foamy.media', settings: { showArtist: false, extra: 1 } }))
result = Prefs.save({ shell: { updateEntryInline() { return false } } }, 'foamy.media', S, {}, 'volumeStep', 7)
assert.equal(JSON.stringify(result.command), JSON.stringify(['omarchy', 'bar', 'set', 'foamy.media', 'volumeStep', '7', '--json']))
assert.equal(Prefs.save(bar, 'foamy.media', S, {}, 'youtubeMprisName', '--evil').ok, false)
assert.equal(Prefs.save(bar, 'foamy.media', S, {}, 'youtubeBrowser', 'vivaldi').ok, false)
for (const left of ['Open panel', 'Play/pause']) {
  assert.equal(P.clickAction('left', left), left === 'Open panel' ? 'panel' : 'playPause')
  assert.equal(P.clickAction('right', left), left === 'Open panel' ? 'playPause' : 'panel')
  assert.equal(P.clickAction('middle', left), 'next')
  assert.equal(P.clickAction('other', left), 'none')
}
const player = { dbusName: 'org.mpris.MediaPlayer2.chromium.instance1', trackTitle: 'Example', metadata: {} }
assert.equal(M.isYoutube(player, 'Example - YouTube', 'chromium'), true)
assert.equal(M.isYoutube(player, 'Example - YouTube', 'vivaldi'), false)
assert.equal(M.isYoutube({ ...player, dbusName: 'org.mpris.MediaPlayer2.chromiumevil' }, 'Example - YouTube', 'chromium'), false)
assert.equal(M.isYoutube(player, 'Unrelated - YouTube', 'chromium'), false)
assert.equal(M.isYoutube({ ...player, metadata: { 'xesam:url': 'https://youtube.com.evil.test/' } }, 'Example - YouTube', 'chromium'), false)
console.log('ok — preferences, saving, click mapping and browser matching tests passed')
