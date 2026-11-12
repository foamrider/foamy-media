import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "harness"
import "plugin" as Media

// The hover tooltip under the installed 4.5 shell (run by
// tests/tooltip-runtime.py). Without a player, then for every scripted track
// of tests/fake-mpris.py: hover the widget, take the string it hands the bar,
// and draw it in the host's own tooltip Text (HostTooltip.qml, lifted from
// Bar.qml). The string must read literally there and in an AutoText Text,
// while a control AutoText Text fed the raw metadata shows that the markup
// would otherwise have been taken as markup.
ShellRoot {
  id: shell
  readonly property string host: Quickshell.env("FOAMY_HOST")
  readonly property var tracks: JSON.parse(tracksFile.text())
  readonly property string wj: "\u2060"
  property int checks: 0
  property int failures: 0
  property int index: 0

  function check(ok, label) {
    checks++
    if (!ok) {
      failures++
      console.log("FOAMY FAIL tooltip " + label)
    }
  }
  function eq(actual, expected, label) {
    check(actual === expected, label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
  }
  function near(actual, expected, label) {
    check(Math.abs(actual - expected) < 0.01, label + ": width " + actual + ", expected " + expected)
  }

  FileView {
    id: tracksFile
    path: Quickshell.env("FOAMY_TRACKS")
    blockLoading: true
  }

  MockBar {
    id: recordingBar
    moduleName: "foamy.media"
    property var tips: []
    function showTooltip(target, text) {
      tips = tips.concat([String(text)])
    }
  }

  FloatingWindow {
    implicitWidth: 1920
    implicitHeight: 1080
    color: "black"
    ScreenSim {
      id: sim
    }
    Media.Panel {
      id: panel
      y: 4
      x: 800
      bar: recordingBar
      moduleName: "foamy.media"
      settings: ({
          id: "foamy.media",
          hideWhenClosed: false
        })
    }
    Column {
      y: 200
      // The host's sink, and three references in the same font.
      HostTooltip {
        id: hostTip
        fontFamily: recordingBar.fontFamily
      }
      Text {
        id: literal
        textFormat: Text.PlainText
        font: hostTip.label.font
      }
      Text {
        id: autoSink
        textFormat: Text.AutoText
        font: hostTip.label.font
      }
      Text {
        id: control
        textFormat: Text.AutoText
        font: hostTip.label.font
      }
    }
  }

  function pointerOf(item) {
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (kid.hoverEnabled === true && kid.pressAndHoldInterval !== undefined && typeof kid.entered === "function")
        return kid
    }
    return null
  }

  // Hover, then check what the bar was handed against `expected` (what a
  // reader must see) in every sink.
  function hover(expected, label, raw, rich) {
    var before = recordingBar.tips.length
    pointerOf(panel).entered()
    eq(recordingBar.tips.length, before + 1, label + ": hovering shows one tooltip")
    var tip = recordingBar.tips[recordingBar.tips.length - 1] || ""
    eq(tip, panel.tooltipText, label + ": the bar gets tooltipText")
    eq(tip.split(wj).join(""), expected, label + ": text")
    for (var i = 0; i < tip.length; i++) {
      if ((tip[i] === "<" || tip[i] === "&") && tip[i + 1] !== wj) {
        check(false, label + ": unguarded " + tip[i] + " at " + i)
        break
      }
    }

    hostTip.tooltipText = tip
    literal.text = expected
    autoSink.text = tip
    eq(hostTip.label.text, tip, label + ": host Text holds the string")
    near(hostTip.label.implicitWidth, literal.implicitWidth, label + ": host tooltip draws it literally")
    eq(hostTip.label.lineCount, 1, label + ": one line in the host tooltip")
    near(autoSink.implicitWidth, literal.implicitWidth, label + ": literal in an AutoText Text too")
    eq(autoSink.lineCount, 1, label + ": one line in an AutoText Text")
    if (rich) {
      // The control: the same metadata without the guard, its images pointed
      // at the control probe, is read as markup by AutoText.
      control.text = raw
      check(Math.abs(control.implicitWidth - literal.implicitWidth) > 1, label + ": control reads raw markup (" + control.implicitWidth + " vs " + literal.implicitWidth + ")")
    }
  }

  Component.onCompleted: Qt.callLater(noPlayer)
  FoamyWait {
    id: wait
  }

  function noPlayer() {
    eq(panel.live, false, "no player yet")
    hover("Spotify is not running", "not running", "", false)
    console.log("FOAMY WAITING FOR PLAYER")
    nextTrack()
  }

  function settled(t) {
    return panel.live && panel.trackTitle === t.title && panel.trackArtist === t.artist && panel.playing === (t.status === "Playing")
  }

  // Each scripted track in turn: wait until the widget shows it, hover,
  // then skip to the next one.
  function nextTrack() {
    var t = shell.tracks[shell.index]
    wait.waitFor(function () {
      return shell.settled(t)
    }, 60000, function (ok) {
      if (!ok) {
        shell.check(false, "track " + shell.index + " never arrived (live " + panel.live + ", title " + JSON.stringify(panel.trackTitle) + ")")
        shell.finish()
        return
      }
      var prefix = t.status === "Playing" ? "" : "Paused — "
      var raw = prefix + t.title + (t.artist ? "  ·  " + t.artist : "")
      raw = raw.split("tooltip-probe.png").join("control-probe.png")
      shell.hover(t.label, "track " + shell.index, raw, t.rich === true)
      if (shell.index === shell.tracks.length - 1) {
        shell.finish()
        return
      }
      shell.index++
      panel.skipNext()
      shell.nextTrack()
    })
  }

  function finish() {
    eq(index, tracks.length - 1, "every scripted track was shown")
    console.log("FOAMY RESULT " + host + " " + checks + " checks, " + failures + " failures")
    finishTimer.start()
  }
  Timer {
    id: finishTimer
    interval: 1500
    onTriggered: {
      console.log("FOAMY DONE")
      Qt.quit()
    }
  }
}
