import QtQuick
import ".." as Dev

// The dev (1.0) UI for the kit's --trio renders: the real 1.0 Panel with its
// MediaPopup fork, opened against the harness bar. The harness bus has no
// MPRIS player, so dev can only show its "not running" view and Settings.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["not-running", "settings"]
  property string previewState: "not-running"
  // 1.0 keeps its popup (id popup) inside Panel.qml, and the harness window
  // that replaces the fork's PanelWindow reparents it into the simulated
  // screen, so look it up in the scene by its owner once it exists.
  property Item found: old
  readonly property Item popup: found

  function findPopup(item, depth) {
    if (!item || depth > 8) return null
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      if (child && child.owner === old && child.borderSpec !== undefined) return child
      var deeper = findPopup(child, depth + 1)
      if (deeper) return deeper
    }
    return null
  }

  Timer {
    interval: 50
    running: preview.found === old
    repeat: true
    onTriggered: {
      var top = preview
      while (top.parent) top = top.parent
      var popup = preview.findPopup(top, 0)
      if (!popup) return
      popup.anchorItem = preview.anchorItem
      preview.found = popup
    }
  }

  Dev.Panel {
    id: old
    bar: preview.bar
    width: 60
    height: 30
    settings: ({ id: "foamy.media", hideWhenClosed: false })
    Component.onCompleted: old.open()
  }
  onPreviewStateChanged: if (previewState === "settings") old.openSettings(); else old.closeSettings()
}
