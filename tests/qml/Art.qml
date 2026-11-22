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
// the network comes back, and never after TLS_UNSUPPORTED; unplugging the
// leading bar's monitor hands the lead on without an error, and the next
// cover is still probed; exit 127 turns covers off and Settings says why.
// The popup shows only the file the helper wrote, never the player's URL,
// and only while it is open.
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
  // The exit code of the probe that a track change stops (null until it exits).
  property var slowExit: null

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
    function onExited(exitCode) {
      shell.exits++
      if (shell.svc.artProbe.pending === "file:///covers/slow.png")
        shell.slowExit = exitCode
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
    }
  }
  // One bar per monitor, made as the 4.5 bar makes them: a Variants over the
  // screens, each bar holding the widget in a Loader, and the widget's
  // component made outside the bars (the bar's widget registry gives every
  // screen the same one). Taking a name out of `screens` unplugs that
  // monitor: its bar is destroyed with the Loader in it.
  property var screens: ["DP-1", "DP-2", "DP-3"]
  Variants {
    id: bars
    model: shell.screens
    Item {
      required property var modelData
      readonly property var panel: slot.item
      parent: barRow
      width: slot.width
      height: slot.height
      Loader {
        id: slot
        sourceComponent: panelComponent
      }
    }
  }
  Component {
    id: panelComponent
    Media.Panel {
      bar: mockBar
      moduleName: "foamy.media"
      settings: ({
          id: "foamy.media",
          hideWhenClosed: false
        })
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
    // cancel() reads back what the slow helper wrote.
    blockAllReads: true
  }
  FileView {
    id: networkFile
    path: Quickshell.env("FOAMY_CONNECTIVITY")
    blockWrites: true
  }

  // The bars of the monitors still plugged in.
  function panels() {
    var found = []
    for (var i = 0; i < bars.instances.length; i++)
      if (bars.instances[i].panel)
        found.push(bars.instances[i].panel)
    return found
  }
  function leader() {
    var all = panels()
    for (var i = 0; i < all.length; i++)
      if (all[i].statusObject().leader)
        return all[i]
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
    var all = panels()
    for (var i = 0; i < all.length; i++)
      all[i].playerModel = model
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
    // The slow helper writes "ok" for the next probe once it has read its
    // own mode, so the track changes only while that probe really runs.
    wait.waitFor(function () {
      modeFile.reload()
      return svc.artProbe.running && svc.artProbe.pending === "file:///covers/slow.png" && modeFile.text() === "ok\n"
    }, 10000, function () {
      play("file:///covers/next.png")
      wait.waitFor(function () {
        return svc.artProbed === "file:///covers/next.png" && !svc.artProbe.running
      }, 10000, settled(function () {
        eq(starts, 4, "the stopped probe and the next one")
        eq(exits, before + 2, "both probes exited")
        // A slow probe does not end by itself; exit 0 would mean no stop happened.
        check(slowExit !== null && slowExit !== 0, "the slow probe was stopped: exit " + slowExit)
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
        shell.unplug()
      })
    }, "the TLS cover is probed")
  }

  // Unplugging the monitor of the leading bar destroys that bar while its
  // member hands the lead on. The harness fails the run on any TypeError in
  // the log; one of the bars left leads, and it asks for the next cover.
  function unplug() {
    modeFile.setText("ok\n")
    var lead = leader()
    var screen = ""
    for (var i = 0; i < bars.instances.length; i++)
      if (bars.instances[i].panel === lead)
        screen = bars.instances[i].modelData
    screens = screens.filter(function (name) {
      return name !== screen
    })
    wait.waitFor(function () {
      var left = panels()
      return left.length === 2 && left[0].member.members === 2
    }, 10000, function () {
      eq(panels().filter(function (panel) {
        return panel.statusObject().leader
      }).length, 1, "one of the two bars left leads")
      var before = starts
      play("file:///covers/u.png")
      wait.waitFor(function () {
        return svc.artProbed === "file:///covers/u.png" && !svc.artProbe.running
      }, 10000, settled(function () {
        eq(starts, before + 1, "the new leader asks for the next cover once")
        shell.missing()
      }), "the next cover is probed after the unplug")
    }, "the unplugged monitor's bar is gone")
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
