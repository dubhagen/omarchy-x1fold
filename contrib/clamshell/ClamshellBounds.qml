import QtQuick
import Quickshell
import Quickshell.Io

// Shared by cloned Omarchy overlays (menu, image picker, OSD, …).
// Reads x1fold state.json so those PanelWindows can inset to the visible
// OLED half without walking the sandboxed host shell.
Item {
  id: root

  property bool clamshell: false
  property real coverRatio: 0.5
  property int overlapPx: 0

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/x1fold/state.json"

  function activeOn(screen) {
    if (!root.clamshell || !screen)
      return false
    return String(screen.name || "").indexOf("eDP") === 0
  }

  function insetFor(screen) {
    if (!root.activeOn(screen))
      return 0
    return Math.max(0, Math.round(screen.height * root.coverRatio) + root.overlapPx)
  }

  function usableHeightFor(screen) {
    if (!screen)
      return 0
    return Math.max(1, screen.height - root.insetFor(screen))
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        root.clamshell = data.clamshell === true
        root.coverRatio = Number(data.cover_ratio || 0.5)
        root.overlapPx = (data.overlap_px === undefined || data.overlap_px === null) ? 0 : Number(data.overlap_px)
      } catch (e) {}
    }
  }
}
