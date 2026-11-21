const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { load } = require('../kit/node-loader.cjs');
const I = { en: require('../i18n/en.json'), no: require('../i18n/no.json') };
const root = path.join(__dirname, '..');
const tokens = s => [...String(s).matchAll(/%[1-9][0-9]*|\{\w+\}/g)].map(m => m[0]).sort();
const forms = v => (typeof v === 'object' ? Object.values(v) : [v]);

// The source text without whole-line `//` comments (usage examples in the
// kit files name strings nothing shows).
function code(file) {
  return fs.readFileSync(file, 'utf8').split('\n').filter(line => !line.trim().startsWith('//')).join('\n');
}

// The string literals an expression can evaluate to: those that start it or
// follow `?` or `:` at its top level. `a === "x" ? "A" : "B"` gives A and B,
// not x. The expression ends at a top-level `,` or `)`, or at the end of the
// line when `toLineEnd` is set (an assignment).
function results(text, start, toLineEnd) {
  const found = [];
  let depth = 0;
  let expectValue = true;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < text.length && text[j] !== c) j += text[j] === '\\' ? 2 : 1;
      if (depth === 0 && expectValue) found.push(JSON.parse('"' + text.slice(i + 1, j).replace(/\\'/g, "'") + '"'));
      expectValue = false;
      i = j;
      continue;
    }
    if (c === '\n' && toLineEnd && depth === 0) break;
    if (/\s/.test(c)) continue;
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') {
      if (depth === 0) break;
      depth--;
    } else if (c === ',' && depth === 0) break;
    expectValue = depth === 0 && (c === '?' || c === ':');
  }
  return found.filter(s => s !== '');
}

// What a file passes to its translator, and assigns to a field it shows
// through one (`assigned`: names of the left-hand side).
function translated(file, assigned = []) {
  const text = code(file);
  const found = [];
  for (const m of text.matchAll(/(?:FoamyI18n\.tn?|root\.tr|root\.translate)\(/g))
    found.push(...results(text, m.index + m[0].length, false));
  for (const name of assigned)
    for (const m of text.matchAll(new RegExp('\\b' + name + ' = ', 'g')))
      found.push(...results(text, m.index + m[0].length, true));
  return found;
}

function assertEnglishEntries(strings, where) {
  for (const s of strings) assert.ok(Object.hasOwn(I.en, s), `${where}: missing catalog entry ${JSON.stringify(s)}`);
}

test('the catalogs agree: English keys are their own value, Norwegian has every key', () => {
  for (const [key, value] of Object.entries(I.en)) {
    assert.equal(typeof value === 'object' ? value.other : value, key, `English source key: ${key}`);
    assert.ok(Object.hasOwn(I.no, key), `Norwegian entry: ${key}`);
    for (const form of forms(I.no[key])) assert.deepEqual(tokens(form), tokens(key), key);
  }
  assert.deepEqual(Object.keys(I.no).sort(), Object.keys(I.en).sort());
});

test('every string the plugin translates has a catalog entry', () => {
  const seen = new Set();
  for (const file of fs.readdirSync(root).filter(f => f.endsWith('.qml'))) {
    // Panel's own refusal is shown through the settings page's translator.
    const strings = translated(path.join(root, file), file === 'Panel.qml' ? ['localError'] : []);
    assertEnglishEntries(strings, file);
    strings.forEach(s => seen.add(s));
  }
  // A scan that stops matching would pass with nothing found.
  assert.ok(seen.size >= 30, `only ${seen.size} translated strings found in the plugin's QML`);
});

test('the kit strings this plugin shows have catalog entries', () => {
  const kit = name => path.join(root, 'kit', name);
  const strings = [
    load('FoamyPrefs').NOT_ALLOWED,
    load('FoamyPrefs').NO_ENTRY,
    load('FoamyNative').UNAVAILABLE_TEXT,
    ...['FoamySettingsHeader.qml', 'FoamySettingsError.qml', 'FoamyMenu.qml', 'FoamyNumberField.qml',
      'FoamyTextSettingField.qml'].flatMap(name => translated(kit(name))),
    ...translated(kit('FoamyPrefsQueue.qml'), ['error']),
    ...translated(kit('SafeTextField.qml'), ['pasteError']),
  ];
  assertEnglishEntries(strings, 'kit');
  // Settings header and error, number field, save errors, the three paste
  // errors and the six edit menu entries at least.
  assert.ok(new Set(strings).size >= 15, `only ${new Set(strings).size} kit strings found`);
});

test('settings labels and options have catalog entries', () => {
  const P = require('../Preferences.js');
  for (const key of Object.keys(P.labels)) assert.ok(Object.hasOwn(I.en, P.labels[key]), `label ${key}`);
  for (const field of P.fields) for (const option of field.options || []) assert.ok(Object.hasOwn(I.en, option), `option ${option}`);
});
