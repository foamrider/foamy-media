"""Check real media layouts and direction-aware keys without loading the media service."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
base = Path(tempfile.mkdtemp(prefix='foamy-media-rtl-'))
app = base / 'app'
app.mkdir()
plugin = app / 'plugin'
shutil.copytree(source, plugin, ignore=shutil.ignore_patterns('.git', 'test', '__pycache__', 'preview.png'))
# Isolate the host QtQuick.Color collision from the direction under test.
for file in plugin.glob('*.qml'):
    text = file.read_text()
    if 'import qs.Commons\n' in text:
        text = text.replace('import qs.Commons\n', 'import qs.Commons\nimport qs.Commons as PreviewCommons\n')
        text = re.sub(r'(?<![\w.])Color\.', 'PreviewCommons.Color.', text)
        file.write_text(text)
for name in ['Commons', 'Ui']:
    (app / name).symlink_to('/usr/share/omarchy/shell/' + name)
runtime = base / 'runtime'
runtime.mkdir(mode=0o700)
qml = '''import QtQuick
import QtTest
import Quickshell
import "plugin" as Plugin
ShellRoot {
  id: shell
  property bool ready: false
  Timer { interval: 400; running: true; onTriggered: shell.ready = true }
  QtObject {
    id: translator
    property string language: "en"
    property string formatLocale: "en-US"
    property bool rightToLeft: false
    function t(key, fallback) { return fallback }
  }
  FloatingWindow {
    visible: true; implicitWidth: 600; implicitHeight: 1800; color: "#24273a"
    Plugin.SettingsPane { id: pane; width: 560; settings: ({}); language: Plugin.FoamyI18n.language }
    Plugin.BrowserPicker { id: picker; y: 1350; width: 560; settings: ({}); candidates: []; language: Plugin.FoamyI18n.language }
    Plugin.MediaDropdown { id: dropdown; y: 1550; width: 300; label: "Output"; options: ["First", "Second"]; value: "First" }
    Text { id: title; text: "مرحبا بالعالم"; property real panOffset: 0; property real overflow: 80; x: MARQUEE_BINDING }
    Plugin.MediaIcon { id: backIcon; name: "arrow-left"; width: 24; height: 24; y: 1500 }
    TestCase {
      name: "MediaDirection"
      when: shell.ready
      onCompletedChanged: if (completed) console.log("RTL_RESULT", qtest_results.passCount, "passed", qtest_results.failCount, "failed")
      function capture(name) {
        var done = false;
        pane.grabToImage(function(result) { verify(result.saveToFile(Qt.resolvedUrl(name + ".png").toString().replace("file://", ""))); done = true });
        tryVerify(function() { return done });
      }
      function cleanupTestCase() { Plugin.FoamyI18n.backend = null }
      function test_direction() {
        Plugin.FoamyI18n.backend = translator;
        var header = findChild(picker, "browserPickerHeader");
        verify(header !== null);
        for (var direction = 0; direction < 2; direction++) {
          translator.rightToLeft = direction === 1;
          translator.language = direction ? "ar" : "en";
          wait(100);
          compare(pane.LayoutMirroring.enabled, !!direction);
          compare(backIcon.mirror, !!direction);
          for (var width of [560, 380]) {
            pane.width = width; wait(100);
            verify(direction ? pane.backTarget.x > width / 2 : pane.backTarget.x < width / 2);
            capture((direction ? "rtl-" : "ltr-") + width);
          }
          var list = findChild(picker, "browserWindowList");
          compare(list.x, direction ? 0 : 20);
          mouseClick(dropdown, dropdown.width / 2, dropdown.height - 10); wait(100);
          var options = findChild(dropdown, "dropdownOptions");
          verify(options !== null); compare(options.LayoutMirroring.enabled, !!direction);
          keyClick(Qt.Key_Escape);
          header.forceActiveFocus(); tryCompare(header, "activeFocus", true);
          keyClick(direction ? Qt.Key_Left : Qt.Key_Right); compare(picker.expanded, true);
          keyClick(direction ? Qt.Key_Right : Qt.Key_Left); compare(picker.expanded, false);
        }
        title.text = "مرحبا بالعالم"; title.panOffset = 0; wait(50); compare(title.x, -80);
        title.panOffset = 80; compare(title.x, 0);
        title.text = "A long English title"; title.panOffset = 0; wait(50); compare(title.x, 0);
        title.panOffset = 80; compare(title.x, -80);
        translator.rightToLeft = false; wait(100);
        compare(pane.LayoutMirroring.enabled, false);
      }
    }
  }
}
'''
# Exercise the production marquee binding without starting media discovery.
expression = re.search(r'x: (horizontalAlignment[^\n]+)', (source / 'Panel.qml').read_text()).group(1)
qml = qml.replace('MARQUEE_BINDING', expression)
(app / 'shell.qml').write_text(qml)
env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
           QT_QPA_PLATFORMTHEME='generic', QT_QUICK_BACKEND='software')
for key in ['WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE']:
    env.pop(key, None)
try:
    result = subprocess.run(['quickshell', '-p', str(app), '--no-color'], env=env, capture_output=True, text=True, timeout=15)
except subprocess.TimeoutExpired as error:
    print(error.stdout, error.stderr)
    raise
output = result.stdout + result.stderr
print(output)
print('Direction captures:', app)
assert result.returncode == 0 and 'RTL_RESULT' in output and '0 failed' in output, output
