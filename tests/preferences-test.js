const assert = require('node:assert/strict')
const test = require('node:test')
const P = require('../Preferences.js')
const Prefs = require('../kit/node-loader.cjs').load('FoamyPrefs', { console: { log() {}, warn() {} } })
const M = require('../Model.js')
const manifest = require('../manifest.json')
const S = P.schema

test('the schema agrees with the manifest', () => {
  assert.deepEqual(P.fields, manifest.barWidget.schema)
  for (const f of P.fields) {
    assert.equal(Prefs.valid(S, f.key, f.defaultValue), true, f.key)
    assert.equal(Prefs.value(S, {}, f.key), manifest.barWidget.defaults[f.key])
    assert.ok(P.labels[f.key], 'settings label for ' + f.key)
  }
})

test('YouTube names and app IDs are constrained', () => {
  // The MPRIS name is a bare name; the app ID any non-blank single line.
  for (const value of ['--help', '-x', 'vivaldi;echo', '$(echo bad)', 'browser\nname', '', ' ', '/usr/bin/vivaldi', 'a'.repeat(201)])
    assert.equal(Prefs.valid(S, 'youtubeMprisName', value), false, JSON.stringify(value))
  for (const value of ['', '   ', 'app\nid', 'x\u007f', 'a'.repeat(201)])
    assert.equal(Prefs.valid(S, 'youtubeAppId', value), false, JSON.stringify(value))
  assert.equal(Prefs.valid(S, 'youtubeAppId', 'vivaldi-youtube.com__-Default'), true)
  assert.equal(Prefs.valid(S, 'youtubeMprisName', 'chromium'), true)
})

test('click mapping and the configured browser name', () => {
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
})
