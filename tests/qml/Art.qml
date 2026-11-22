import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "harness"
import "plugin" as Media
import "plugin/kit"
import "plugin/Model.js" as Model

// The cover service through its real Process (tests/art-runtime.py): three
// bars share one probe; only the last URL of a burst is probed; a track
// change stops a running probe, which still counts as started; a remote
// cover waits for the network, is retried 2.5, 5 and 10 s apart, again after
// the network comes back, and never after TLS_UNSUPPORTED; exit 127 turns
// covers off and Settings says why. The popup shows only the file the
// helper wrote, never the player's URL, and only while it is open.
ShellRoot {
  id: shell
  property int checks: 0
  property int failures: 0
  readonly property string out: Quickshell.env("FOAMY_OUT")
  readonly property string probedUrl: Model.fileUrl(out + "/probed.png")
  readonly property QtObject svc: Media.MediaService
  // Probes started and exited, counted from the service's own Process.
  property int starts: 0
  property int exits: 0

  function check(ok, label) {
    checks++
    if (!ok) {
      failures++
      console.log("FOAMY FAIL " + label)
    }
  }
  function eq(actual, expected, label) {
    check(actual === expected, label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
  }

  Connections {
    target: shell.svc.artProbe
    function onRunningChanged() {
      if (shell.svc.artProbe.running)
        shell.starts++
    }
    function onExited() {
      shell.exits++
    }
  }

  FloatingWindow {
    implicitWidth: 1920
    implicitHeight: 1080
    color: "black"
    ScreenSim {}
    Row {
      id: barRow
      y: 4
      x: 1200
      spacing: 40
      Repeater {
        id: panels
        model: 3
        Media.Panel {
          bar: mockBar
          moduleName: "foamy.media"
          settings: ({
              id: "foamy.media",
              hideWhenClosed: false
            })
        }
      }
    }
  }

  MockBar {
    id: mockBar
    moduleName: "foamy.media"
  }
  FoamyWait {
    id: wait
  }
  // What the fake helper does next, and the connectivity the fake
  // NetworkManager reports (4 full, 1 none).
  FileView {
    id: modeFile
    path: shell.out + "/helper-mode"
    blockWrites: true
  }
  FileView {
    id: networkFile
    path: Quickshell.env("FOAMY_CONNECTIVITY")
    blockWrites: true
  }

  function leader() {
    for (var i = 0; i < 3; i++)
      if (panels.itemAt(i).statusObject().leader)
        return panels.itemAt(i)
    return null
  }
  // A playing Spotify with this cover, on every bar (a new object, since a
  // plain one does not notify).
  function play(url) {
    var model = {
      values: [
        {
          dbusName: "org.mpris.MediaPlayer2.spotify",
          identity: "Spotify",
          isPlaying: true,
          trackTitle: "T",
          trackArtist: "A",
          trackArtUrl: url,
          canSeek: false,
          shuffleSupported: false,
          // The leader's position tick re-reads through this signal.
          positionChanged: function () {}
        }
      ]
    }
    for (var i = 0; i < 3; i++)
      panels.itemAt(i).playerModel = model
  }
  function images(item, found) {
    if (!item)
      return found
    if (item.status !== undefined && item.source !== undefined && item.sourceSize !== undefined)
      found.push(String(item.source))
    for (var i = 0; i < (item.children || []).length; i++)
      images(item.children[i], found)
    return found
  }
  function findToggle(item, key) {
    if (!item)
      return null
    if (item.key === key && item.checked !== undefined)
      return item
    for (var i = 0; i < (item.children || []).length; i++) {
      var hit = findToggle(item.children[i], key)
      if (hit)
        return hit
    }
    return null
  }

  Component.onCompleted: Qt.callLater(cover)

  // Quickshell reports a started Process as running a moment after the
  // request, so a check that no further probe started reads `starts` only
  // after a short absence window.
  function settled(then) {
    return function () {
      wait.after(500, then)
    }
  }

  // Three bars, one probe, and only the helper's file is shown.
  function cover() {
    play("file:///covers/My%20Cover.png")
    wait.waitFor(function () {
      return svc.artFile !== "" && !svc.artProbe.running
    }, 10000, settled(function () {
      eq(starts, 1, "three bars ask for one probe")
      eq(svc.artFile, out + "/probed.png", "the cover is the file the helper wrote")
      var lead = leader()
      lead.open()
      wait.waitFor(function () {
        return lead.popup.bodyItem !== null && lead.imagesActive
      }, 10000, function () {
        var view = lead.popup.bodyItem
        eq(lead.artSource, probedUrl, "the popup's cover is the probed file")
        eq(view.band.imageSource.toString(), probedUrl, "and so is the band picture")
        // The kit's icons are data: URLs; only file images are of interest.
        var sources = images(view, []).filter(function (s) {
          return s.indexOf("data:") !== 0
        })
        check(sources.indexOf(probedUrl) >= 0, "an image shows the probed file: " + JSON.stringify(sources))
        check(sources.every(function (s) {
          return s.indexOf("/covers/") < 0
        }), "no image names the player's URL: " + JSON.stringify(sources))
        lead.close()
        wait.waitFor(function () {
          return !lead.imagesActive
        }, 10000, function () {
          eq(lead.artSource, "", "no cover is decoded once the popup has closed")
          eq(view.band.imageSource.toString(), "", "and the band holds no picture")
          shell.burst()
        }, "covers are released after the popup closes")
      }, "the popup opens")
    }), "the first cover is probed")
  }

  // Skipping through tracks probes only the one that settles.
  function burst() {
    play("file:///covers/a.png")
    play("file:///covers/b.png")
    play("file:///covers/c.png")
    wait.waitFor(function () {
      return svc.artProbed === "file:///covers/c.png" && !svc.artProbe.running
    }, 10000, settled(function () {
      eq(starts, 2, "a burst of track changes starts one probe")
      shell.cancel()
    }), "the last cover of a burst is probed")
  }

  // A track change while a probe runs stops that probe, and the new
  // track's cover is probed once it has exited.
  function cancel() {
    modeFile.setText("slow\n")
    var before = exits
    play("file:///covers/slow.png")
    wait.waitFor(function () {
      return svc.artProbe.running && svc.artProbe.pending === "file:///covers/slow.png"
    }, 10000, function () {
      modeFile.setText("ok\n")
      play("file:///covers/next.png")
      wait.waitFor(function () {
        return svc.artProbed === "file:///covers/next.png" && !svc.artProbe.running
      }, 10000, settled(function () {
        eq(starts, 4, "the stopped probe and the next one")
        eq(exits, before + 2, "both probes exited")
        eq(svc.artFile, out + "/probed.png", "the next track's cover is shown")
        shell.offline()
      }), "the next track's cover is probed after the stopped one")
    }, "the slow probe runs")
  }

  // A remote cover waits for the network.
  function offline() {
    modeFile.setText("http\n")
    play("https://i.scdn.co/image/x")
    wait.waitFor(function () {
      return svc.artUrl === "https://i.scdn.co/image/x" && !svc.artProbeDelay.running
    }, 10000, settled(function () {
      eq(starts, 4, "no probe for a remote cover while offline")
      eq(svc.artFile, "", "and no previous cover is kept")
      networkFile.setText("4\n")
      wait.waitFor(function () {
        return exits === 5 && svc.artRetry.running
      }, 15000, function () {
        eq(svc.artRetry.interval, 2500, "the first retry waits 2.5 s")
        retry(5000, function () {
          retry(10000, function () {
            retry(0, shell.reconnect)
          })
        })
      }, "once online the cover is fetched, and the failure is retried")
    }), "the remote cover waits")
  }
  // Fire the pending retry now instead of waiting it out; `interval` is the
  // next backoff, or 0 when none may follow.
  function retry(interval, then) {
    var before = exits
    svc.artRetry.stop()
    svc.artRetry.triggered()
    wait.waitFor(function () {
      return exits === before + 1
    }, 10000, function () {
      // The exit handler decides on a retry a moment later.
      Qt.callLater(function () {
        if (interval > 0) {
          eq(svc.artRetry.running, true, "a failed retry is retried again")
          eq(svc.artRetry.interval, interval, "the next retry waits " + interval + " ms")
        } else {
          eq(svc.artRetry.running, false, "no fourth retry")
          eq(svc.artRetries, 3, "three retries")
        }
        then()
      })
    }, "a retry runs")
  }
  // The network going away and back starts the backoff over.
  function reconnect() {
    networkFile.setText("1\n")
    wait.waitFor(function () {
      return !svc.networkReady
    }, 10000, function () {
      eq(svc.artRetries, 0, "losing the network resets the retries")
      var before = exits
      networkFile.setText("4\n")
      wait.waitFor(function () {
        return exits === before + 1 && svc.artRetry.running
      }, 15000, function () {
        eq(svc.artRetry.interval, 2500, "back online, the backoff starts over")
        shell.tls()
      }, "back online the cover is fetched again")
    }, "the network goes away")
  }

  // A CPU without the instructions HTTPS needs won't gain them on a retry.
  function tls() {
    modeFile.setText("tls\n")
    var before = exits
    play("https://i.scdn.co/image/y")
    wait.waitFor(function () {
      return exits === before + 1
    }, 10000, function () {
      Qt.callLater(function () {
        eq(svc.artProbe.failure, "TLS_UNSUPPORTED", "the failure code is read")
        eq(svc.artRetry.running, false, "TLS_UNSUPPORTED is not retried")
        shell.missing()
      })
    }, "the TLS cover is probed")
  }

  // No helper for this CPU: covers stay off, Settings says why, and the
  // helper is not started again.
  function missing() {
    modeFile.setText("missing\n")
    play("file:///covers/m.png")
    wait.waitFor(function () {
      return svc.artHelperUnavailable
    }, 10000, function () {
      eq(svc.artFile, "", "no cover without a helper")
      var lead = leader()
      lead.openSettings()
      wait.waitFor(function () {
        return lead.popup.bodyItem !== null && shell.findToggle(lead.popup.bodyItem, "artBackground") !== null
      }, 10000, function () {
        var toggle = shell.findToggle(lead.popup.bodyItem, "artBackground")
        eq(toggle.description, FoamyI18n.t("This plugin's helper isn't available for this CPU."), "the artwork setting says why")
        lead.close()
        var before = starts
        play("file:///covers/n.png")
        wait.waitFor(function () {
          return svc.artUrl === "file:///covers/n.png" && !svc.artProbeDelay.running
        }, 10000, settled(function () {
          eq(starts, before, "the missing helper is not started again")
          shell.finish()
        }), "the next track's cover is requested")
      }, "the artwork setting is shown")
    }, "exit 127 marks the helper unavailable")
  }

  function finish() {
    console.log("FOAMY RESULT 4.5/en " + checks + " checks, " + failures + " failures")
    console.log("FOAMY DONE")
    Qt.quit()
  }
}
