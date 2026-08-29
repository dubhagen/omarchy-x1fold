import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string script: pluginDir + "/bin/x1fold"
  readonly property string statePath: home + "/.local/state/omarchy/x1fold/state.json"
  readonly property string screensaverClass: "org.omarchy.screensaver"

  property bool clamshell: false
  property real coverRatio: 0.5
  property int overlapPx: 0
  property int orientationIndex: 3
  property bool autorotate: false
  property string statusLabel: "Landscape"
  property string statusIcon: "󰹑"
  property string pendingCommand: ""
  property var screensaverWindows: ({})

  function refreshFromText(text) {
    try {
      var data = JSON.parse(text || "{}")
      clamshell = data.clamshell === true
      coverRatio = Number(data.cover_ratio || 0.5)
      overlapPx = (data.overlap_px === undefined || data.overlap_px === null) ? 0 : Number(data.overlap_px)
      orientationIndex = Number(data.transform || 0)
      autorotate = data.autorotate === true
      if (orientationIndex % 2 === 0) {
        statusLabel = orientationIndex === 2 ? "Portrait (flipped)" : "Portrait"
        statusIcon = clamshell ? "󰌌" : "󰁞"
      } else {
        statusLabel = orientationIndex === 1 ? "Landscape (flipped)" : "Landscape"
        statusIcon = clamshell ? "󰌌" : "󰹑"
      }
    } catch (e) {}
  }

  function runCmd(args) {
    if (cmdProc.running) {
      pendingCommand = args.join("\x1f")
      return
    }
    var argv = [root.script]
    for (var i = 0; i < args.length; i++) argv.push(args[i])
    cmdProc.command = argv
    cmdProc.running = true
  }

  function startDaemon() {
    if (!daemonProc.running) daemonProc.running = true
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.refreshFromText(text())
    onLoadFailed: {}
  }

  Process {
    id: cmdProc
    onExited: {
      stateFile.reload()
      if (root.pendingCommand !== "") {
        var next = root.pendingCommand.split("\x1f")
        root.pendingCommand = ""
        root.runCmd(next)
      }
    }
  }

  Process {
    id: daemonProc
    command: [root.script, "daemon"]
    running: false
    onExited: daemonRestart.restart()
  }

  Timer {
    id: daemonRestart
    interval: 500
    repeat: false
    onTriggered: if (!daemonProc.running) daemonProc.running = true
  }

  Process {
    id: applyProc
    command: [root.script, "apply", "--quiet"]
  }

  function screensaverOpen() {
    var n = 0
    for (var key in root.screensaverWindows) if (root.screensaverWindows[key]) n++
    return n > 0
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    var data = String(event && event.data ? event.data : "")
    var parts = data.split(",")
    if (name === "openwindow" && String(parts[2] || "") === root.screensaverClass) {
      var next = Object.assign({}, root.screensaverWindows)
      next[String(parts[0] || "")] = true
      root.screensaverWindows = next
    } else if (name === "closewindow") {
      var address = String(parts[0] || "")
      if (root.screensaverWindows[address]) {
        var cleared = Object.assign({}, root.screensaverWindows)
        delete cleared[address]
        root.screensaverWindows = cleared
        restoreTimer.restart()
      }
    } else if (name === "monitoradded" || name === "configreloaded") {
      restoreTimer.restart()
    }
  }

  Timer {
    id: restoreTimer
    interval: 400
    repeat: false
    onTriggered: if (!root.screensaverOpen()) applyProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Component.onCompleted: {
    startDaemon()
    applyProc.running = true
  }

  IpcHandler {
    target: "mattd.x1fold"

    function status(): string {
      return JSON.stringify({
        clamshell: root.clamshell,
        coverRatio: root.coverRatio,
        transform: root.orientationIndex,
        autorotate: root.autorotate,
        label: root.statusLabel,
        icon: root.statusIcon
      })
    }

    function rotate(arg: string): string {
      root.runCmd(["rotate", arg || "cycle"])
      return "ok"
    }

    function clamshell(arg: string): string {
      root.runCmd(["clamshell", arg || "toggle"])
      return "ok"
    }

    function autorotate(arg: string): string {
      root.runCmd(["autorotate", arg || "toggle"])
      return "ok"
    }

    function osk(arg: string): string {
      root.runCmd(["osk", arg || "toggle"])
      return "ok"
    }

    function tablet(): string {
      root.runCmd(["tablet"])
      return "ok"
    }

    function apply(): string {
      root.runCmd(["apply"])
      return "ok"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: mask
      required property var modelData

      screen: modelData
      visible: root.clamshell && String(modelData.name || "").indexOf("eDP") === 0
      anchors { left: true; right: true; bottom: true }
      implicitHeight: Math.max(0, Math.round(modelData.height * root.coverRatio) + root.overlapPx)
      color: "#000000"
      WlrLayershell.namespace: "mattd-x1fold-mask"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
    }
  }
}
