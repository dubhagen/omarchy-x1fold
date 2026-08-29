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
  readonly property int reservedLogical: {
    if (!clamshell)
      return 0
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var sc = screens[i]
      if (String(sc.name || "").indexOf("eDP") === 0)
        return Math.max(0, Math.round(sc.height * coverRatio) + overlapPx)
    }
    return 0
  }

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

  Process {
    id: fsProc
  }

  Process {
    id: ssProc
  }

  Timer {
    id: ssRetry
    interval: 100
    repeat: true
    property int left: 0
    onTriggered: {
      if (!root.clamshell || left <= 0) {
        stop()
        left = 0
        return
      }
      left -= 1
      if (!ssProc.running) {
        ssProc.command = [root.script, "constrain-screensaver"]
        ssProc.running = true
      }
      if (left <= 0)
        stop()
    }
  }

  Timer {
    id: overlayTimer
    interval: 80
    repeat: false
    onTriggered: root.constrainOverlays()
  }

  Timer {
    id: overlayWatch
    interval: 750
    repeat: true
    running: root.clamshell
    onTriggered: root.constrainOverlays()
  }

  function screensaverOpen() {
    var n = 0
    for (var key in root.screensaverWindows) if (root.screensaverWindows[key]) n++
    return n > 0
  }

  function layerNamespace(item) {
    try {
      if (item && item.WlrLayershell && item.WlrLayershell.namespace)
        return String(item.WlrLayershell.namespace)
    } catch (e) {}
    return ""
  }

  function layerIsBackground(item) {
    try {
      return item && item.WlrLayershell && item.WlrLayershell.layer === WlrLayer.Background
    } catch (e) {}
    return false
  }

  function skipOverlay(item) {
    var ns = root.layerNamespace(item)
    if (ns === "mattd-x1fold-mask" || ns === "omarchy-background" || ns === "omarchy-bar")
      return true
    if (ns.indexOf("lock") !== -1 || ns.indexOf("screensaver") !== -1)
      return true
    if (root.layerIsBackground(item))
      return true
    return false
  }

  function constrainOneOverlay(item) {
    if (!item)
      return
    var inset = root.reservedLogical
    root.nudgeOverlayCard(item, inset)
    if (item.exclusionMode === undefined || !item.anchors)
      return
    if (!item.anchors.top || !item.anchors.bottom)
      return
    if (root.skipOverlay(item))
      return
    if ("cardTop" in item) {
      if (!inset) {
        if (item.cardTop !== -1)
          item.cardTop = -1
      } else {
        var cardH = 0
        try {
          var kids = item.children
          for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k && k.height > 80 && k.width > 80 && k.height < item.height - 40)
              cardH = Math.max(cardH, k.height)
          }
        } catch (e) {}
        if (!cardH)
          cardH = Math.min(480, Math.round((item.height - inset) * 0.55))
        var usable = Math.max(0, item.height - inset)
        var top = Math.max(12, Math.round((usable - cardH) / 2))
        if (item.cardTop !== top)
          item.cardTop = top
      }
    }
    if (item.margins === undefined)
      return
    var m = item.margins
    if (m.bottom === inset)
      return
    try {
      item.margins = {
        left: m.left || 0,
        right: m.right || 0,
        top: m.top || 0,
        bottom: inset
      }
    } catch (e) {}
  }

  function nudgeOverlayCard(item, inset) {
    if (!item)
      return
    try {
      if (item.anchors && item.anchors.centerIn) {
        var off = inset ? -Math.round(inset / 2) : 0
        if (item.anchors.verticalCenterOffset !== off)
          item.anchors.verticalCenterOffset = off
      }
    } catch (e) {}
    try {
      if (item.anchors && item.anchors.bottom && !item.anchors.top && !item.anchors.centerIn) {
        if (item._x1foldBaseBM === undefined)
          item._x1foldBaseBM = item.anchors.bottomMargin || 0
        var want = item._x1foldBaseBM + inset
        if (item.anchors.bottomMargin !== want)
          item.anchors.bottomMargin = want
      }
    } catch (e) {}
  }

  function visitPluginTree(item, fn) {
    if (!item)
      return
    var seen = []
    function visit(node, depth) {
      if (!node || depth > 5 || seen.length > 80)
        return
      for (var s = 0; s < seen.length; s++)
        if (seen[s] === node)
          return
      seen.push(node)
      try { fn(node) } catch (e) {}
      var lists = []
      try { if (node.children) lists.push(node.children) } catch (e) {}
      // PanelWindow is a Window, so it lives in `data` of the plugin root,
      // not in the Item children list of the same scene.
      if (depth === 0) {
        try { if (node.data) lists.push(node.data) } catch (e) {}
      }
      for (var li = 0; li < lists.length; li++) {
        var list = lists[li]
        var n = list.length
        for (var i = 0; i < n; i++)
          visit(list[i], depth + 1)
      }
    }
    visit(item, 0)
  }

  function eachPluginRoot(fn) {
    if (!root.shell)
      return
    var loaders = root.shell.panelLoaders || {}
    for (var id in loaders) {
      if (loaders[id] && loaders[id].item)
        fn(loaders[id].item)
    }
    if (typeof root.shell.serviceFor === "function") {
      var services = ["omarchy.notifications", "omarchy.osd"]
      for (var si = 0; si < services.length; si++)
        fn(root.shell.serviceFor(services[si]))
    }
  }

  function constrainOverlays() {
    root.eachPluginRoot(function(pluginRoot) {
      root.visitPluginTree(pluginRoot, function(node) { root.constrainOneOverlay(node) })
    })
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    var data = String(event && event.data ? event.data : "")
    var parts = data.split(",")
    if (name === "openwindow" && String(parts[2] || "") === root.screensaverClass) {
      var next = Object.assign({}, root.screensaverWindows)
      next[String(parts[0] || "")] = true
      root.screensaverWindows = next
      if (root.clamshell) {
        ssProc.command = [root.script, "constrain-screensaver", String(parts[0] || "")]
        ssProc.running = true
        ssRetry.left = 6
        ssRetry.restart()
      }
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
    } else if (name === "fullscreen") {
      if (root.clamshell && String(parts[1] || "") === "1") {
        fsProc.command = [root.script, "constrain-fullscreen", String(parts[0] || "")]
        fsProc.running = true
      }
    } else if (name === "openlayer" || name === "createlayer") {
      overlayTimer.restart()
    }
  }

  onClamshellChanged: overlayTimer.restart()
  onCoverRatioChanged: overlayTimer.restart()
  onOverlapPxChanged: overlayTimer.restart()

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
    overlayTimer.restart()
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
