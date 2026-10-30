// kit/FoamyPrefs.js is a QML JS library; load it in a sandbox without its pragma.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const sandbox = { module: { exports: {} }, console: { log() {}, warn() {} } };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../kit/FoamyPrefs.js'), 'utf8').replace(/^\.pragma library\s*$/m, ''), sandbox);
module.exports = sandbox.module.exports;
