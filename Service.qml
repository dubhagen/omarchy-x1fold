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
  property bool barHiddenByUs: false
  property bool pendingBarSync: false
  property bool ssDismissArmed: false
  property bool ssDismissing: false
  property bool ssSawIdle: false
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

  Process {
    id: ssDismissProc
    onExited: {
      root.ssDismissing = false
      if (!root.screensaverOpen())
        root.restoreBarAfterFullscreen()
    }
  }

  Process {
    id: barSyncProc
    onExited: {
      if (root.pendingBarSync) {
        root.pendingBarSync = false
        barSyncProc.command = [root.script, "sync-bar"]
        barSyncProc.running = true
      }
    }
  }

  Timer {
    id: ssRetry
    interval: 80
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
    id: fsRetry
    interval: 80
    repeat: true
    property int left: 0
    onTriggered: {
      if (!root.clamshell || left <= 0) {
        stop()
        left = 0
        return
      }
      left -= 1
      if (!fsProc.running) {
        fsProc.command = [root.script, "constrain-fullscreen"]
        fsProc.running = true
      }
      if (left <= 0)
        stop()
    }
  }

  Timer {
    id: overlayTimer
    interval: 16
    repeat: true
    property int left: 0
    onTriggered: {
      root.constrainOverlays()
      left -= 1
      if (left <= 0)
        stop()
    }
  }

  Timer {
    id: overlayWatch
    interval: 750
    repeat: true
    running: root.clamshell
    onTriggered: root.constrainOverlays()
  }

  function requestOverlayConstrain() {
    overlayTimer.left = 40
    overlayTimer.restart()
  }

  function screensaverOpen() {
    var n = 0
    for (var key in root.screensaverWindows) if (root.screensaverWindows[key]) n++
    return n > 0
  }

  function setBarHidden(hidden) {
    if (root.shell && root.shell.bar && root.shell.bar.barHidden !== undefined)
      root.shell.bar.barHidden = hidden
  }

  function requestBarSync() {
    if (barSyncProc.running) {
      root.pendingBarSync = true
      return
    }
    barSyncProc.command = [root.script, "sync-bar"]
    barSyncProc.running = true
  }

  function hideBarForFullscreen() {
    if (!root.clamshell)
      return
    if (root.shell && root.shell.bar && root.shell.bar.barHidden && !root.barHiddenByUs)
      return
    root.barHiddenByUs = true
    root.setBarHidden(true)
    root.requestBarSync()
  }

  function restoreBarAfterFullscreen() {
    if (!root.barHiddenByUs)
      return
    if (root.screensaverOpen())
      return
    root.barHiddenByUs = false
    root.setBarHidden(false)
    root.requestBarSync()
  }

  function dismissScreensaver() {
    if (!root.clamshell || root.ssDismissing)
      return
    if (!root.screensaverOpen() && !root.barHiddenByUs)
      return
    root.ssDismissing = true
    root.ssDismissArmed = false
    root.barHiddenByUs = false
    root.setBarHidden(false)
    if (ssDismissProc.running)
      return
    ssDismissProc.command = [root.script, "dismiss-screensaver"]
    ssDismissProc.running = true
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
    if (ns.indexOf("omarchy-bar-") === 0)
      return true
    if (ns.indexOf("lock") !== -1 || ns.indexOf("screensaver") !== -1)
      return true
    if (root.layerIsBackground(item))
      return true
    return false
  }

  function isLayerPanel(item) {
    if (!item)
      return false
    try {
      return item.exclusionMode !== undefined && item.anchors !== undefined
    } catch (e) {
      return false
    }
  }

  function panelScreenHeight(item) {
    if (item.screen && item.screen.height)
      return item.screen.height
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "").indexOf("eDP") === 0)
        return screens[i].height
    }
    return 0
  }

  function marginEdge(margins, edge) {
    try {
      if (!margins)
        return 0
      var v = Number(margins[edge])
      return isNaN(v) ? 0 : v
    } catch (e) {
      return 0
    }
  }

  // PanelWindow is a C++ type and rejects dynamic properties, so original
  // margins / bounded flags live here instead of on the overlay objects.
  property var panelBounds: []

  function panelBoundState(item) {
    var list = root.panelBounds
    for (var i = 0; i < list.length; i++)
      if (list[i].item === item)
        return list[i]
    var st = { item: item, orig: null, watch: false, bounded: false }
    list.push(st)
    return st
  }

  function panelIsBounded(item) {
    var list = root.panelBounds
    for (var i = 0; i < list.length; i++)
      if (list[i].item === item)
        return !!list[i].bounded
    return false
  }

  function capturePanelOrig(item, st) {
    if (st.orig)
      return
    var a = item.anchors
    var m = item.margins
    st.orig = {
      top: !!a.top,
      bottom: !!a.bottom,
      left: !!a.left,
      right: !!a.right,
      marginTop: root.marginEdge(m, "top"),
      marginBottom: root.marginEdge(m, "bottom"),
      marginLeft: root.marginEdge(m, "left"),
      marginRight: root.marginEdge(m, "right"),
      implicitHeight: item.implicitHeight
    }
  }

  function writeMargins(target, spec) {
    if (!target || target.margins === undefined)
      return
    var m = target.margins
    m.left = spec.left
    m.right = spec.right
    m.top = spec.top
    m.bottom = spec.bottom
    target.margins = m
  }

  function writeAnchors(target, spec) {
    if (!target || target.anchors === undefined)
      return
    var a = target.anchors
    a.left = spec.left
    a.right = spec.right
    a.top = spec.top
    a.bottom = spec.bottom
    target.anchors = a
  }

  function setPanelMargins(item, spec) {
    try { root.writeMargins(item, spec) } catch (e) {}
    try { root.writeMargins(item.WlrLayershell, spec) } catch (e2) {}
  }

  function setPanelAnchors(item, spec) {
    try { root.writeAnchors(item, spec) } catch (e) {}
    try { root.writeAnchors(item.WlrLayershell, spec) } catch (e2) {}
  }

  function watchPanel(item, st) {
    if (st.watch)
      return
    st.watch = true
    function reapply() {
      Qt.callLater(function() { root.applyPanelBoundary(item) })
    }
    try { item.visibleChanged.connect(reapply) } catch (e) {}
    try { item.backingWindowVisibleChanged.connect(reapply) } catch (e2) {}
  }

  // Shrink overlay PanelWindows to the visible OLED half in clamshell.
  // Omarchy overlays bind all four edges, which ignores implicitHeight, so
  // this insets via layer-shell margins instead of fighting those anchors.
  // ExclusionMode stays Ignore: exclusive zones would reflow tiled windows.
  // inset 0 restores the captured margins.
  function applyPanelBoundary(item) {
    if (!root.isLayerPanel(item) || root.skipOverlay(item))
      return false
    var st = root.panelBoundState(item)
    root.capturePanelOrig(item, st)
    root.watchPanel(item, st)
    var screenH = root.panelScreenHeight(item)
    if (!screenH)
      return false
    var inset = root.reservedLogical
    var orig = st.orig
    try {
      var visible = false
      try { visible = !!item.visible } catch (e1) {}
      var usable = Math.max(1, screenH - inset)
      if (inset > 0) {
        root.setPanelMargins(item, {
          top: orig.marginTop,
          bottom: orig.marginBottom + inset,
          left: orig.marginLeft,
          right: orig.marginRight
        })
        // Newly mapped overlays sometimes ignore margins until the bottom
        // anchor is dropped. implicitHeight then sizes the surface.
        if (visible && Math.abs(item.height - usable) > 16) {
          root.setPanelAnchors(item, {
            top: true,
            bottom: false,
            left: orig.left || true,
            right: orig.right || true
          })
          root.setPanelMargins(item, {
            top: orig.marginTop,
            bottom: orig.marginBottom,
            left: orig.marginLeft,
            right: orig.marginRight
          })
          try { item.implicitHeight = usable } catch (e2) {}
        }
        st.bounded = !visible || Math.abs(item.height - usable) <= 16
        if ("cardTop" in item && st.bounded && item.cardTop !== -1)
          item.cardTop = -1
        return st.bounded
      }
      root.setPanelAnchors(item, {
        top: orig.top,
        bottom: orig.bottom,
        left: orig.left,
        right: orig.right
      })
      root.setPanelMargins(item, {
        top: orig.marginTop,
        bottom: orig.marginBottom,
        left: orig.marginLeft,
        right: orig.marginRight
      })
      if (orig.implicitHeight !== undefined) {
        try { item.implicitHeight = orig.implicitHeight } catch (e3) {}
      }
      st.bounded = false
      return true
    } catch (e) {
      st.bounded = false
      return false
    }
  }

  function parentPanelBounded(item) {
    var p = item
    for (var i = 0; i < 6 && p; i++) {
      if (root.panelIsBounded(p))
        return true
      try { p = p.parent } catch (e) { return false }
    }
    return false
  }

  function constrainOneOverlay(item) {
    if (!item)
      return
    if (root.isLayerPanel(item))
      root.applyPanelBoundary(item)
    var extra = (root.panelIsBounded(item) || root.parentPanelBounded(item)) ? 0 : root.reservedLogical
    root.nudgeOverlayCard(item, extra)
    if (!("cardTop" in item))
      return
    if (!extra) {
      if (item.cardTop !== -1)
        item.cardTop = -1
      return
    }
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
      cardH = Math.min(480, Math.round((item.height - extra) * 0.55))
    var usable = Math.max(0, item.height - extra)
    var top = Math.max(12, Math.round((usable - cardH) / 2))
    if (item.cardTop !== top)
      item.cardTop = top
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

  function eachPluginRoot(fn) {
    if (!root.shell)
      return
    var loaders = root.shell.panelLoaders || {}
    var id
    try {
      for (id in loaders) {
        try {
          if (loaders[id] && loaders[id].item)
            fn(loaders[id].item)
        } catch (e1) {}
      }
    } catch (e) {}
    try {
      var svcs = root.shell._services || {}
      for (id in svcs)
        fn(svcs[id])
    } catch (e2) {
      if (typeof root.shell.serviceFor === "function") {
        var names = ["omarchy.notifications", "omarchy.osd", "omarchy.polkit"]
        for (var si = 0; si < names.length; si++)
          fn(root.shell.serviceFor(names[si]))
      }
    }
    if (root.shell.bar)
      fn(root.shell.bar)
    try {
      var slots = root.shell.bar && root.shell.bar.moduleSlots
      if (slots) {
        for (var i = 0; i < slots.length; i++) {
          var slot = slots[i]
          if (slot && slot.activeItem)
            fn(slot.activeItem)
        }
      }
    } catch (e3) {}
  }

  function collectLayerPanels() {
    var out = []
    var seen = []
    function add(node) {
      if (!node || !root.isLayerPanel(node))
        return
      for (var s = 0; s < seen.length; s++)
        if (seen[s] === node)
          return
      seen.push(node)
      out.push(node)
    }
    var visited = []
    function takeDataPanels(obj) {
      if (!obj)
        return
      for (var v = 0; v < visited.length; v++)
        if (visited[v] === obj)
          return
      visited.push(obj)
      add(obj)
      try {
        var d = obj.data
        var n = d ? d.length : 0
        for (var i = 0; i < n; i++) {
          var child = null
          try { child = d[i] } catch (e1) { continue }
          add(child)
          try {
            var inst = child && child.instances
            if (inst) {
              for (var j = 0; j < inst.length; j++)
                add(inst[j])
            }
          } catch (e2) {}
          try { if (child && child.item) takeDataPanels(child.item) } catch (e6) {}
        }
      } catch (e) {}
      try {
        var inst2 = obj.instances
        if (inst2) {
          for (var k = 0; k < inst2.length; k++)
            add(inst2[k])
        }
      } catch (e3) {}
      try { if (obj.item) takeDataPanels(obj.item) } catch (e4) {}
      try {
        if (obj.panelLoader && obj.panelLoader.item)
          takeDataPanels(obj.panelLoader.item)
      } catch (e5) {}
    }
    root.eachPluginRoot(function(pluginRoot) { takeDataPanels(pluginRoot) })
    return out
  }

  function constrainOverlays() {
    var panels = root.collectLayerPanels()
    for (var i = 0; i < panels.length; i++) {
      var node = panels[i]
      root.constrainOneOverlay(node)
      try {
        var kids = node.children
        if (kids) {
          for (var k = 0; k < kids.length; k++)
            root.constrainOneOverlay(kids[k])
        }
      } catch (e) {}
    }
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
        root.ssDismissing = false
        root.ssDismissArmed = false
        root.ssSawIdle = false
        ssArmTimer.restart()
        root.hideBarForFullscreen()
        ssProc.command = [root.script, "constrain-screensaver", String(parts[0] || "")]
        ssProc.running = true
        ssRetry.left = 20
        ssRetry.restart()
      }
    } else if (name === "closewindow") {
      var address = String(parts[0] || "")
      if (root.screensaverWindows[address]) {
        var cleared = Object.assign({}, root.screensaverWindows)
        delete cleared[address]
        root.screensaverWindows = cleared
        if (!root.screensaverOpen()) {
          root.ssDismissArmed = false
          if (!root.ssDismissing)
            root.restoreBarAfterFullscreen()
          ssProc.command = [root.script, "cursor", "show"]
          ssProc.running = true
        }
        restoreTimer.restart()
      }
    } else if (name === "monitoradded" || name === "configreloaded") {
      restoreTimer.restart()
    } else if (name === "fullscreen") {
      // socket2 data is "0"/"1". Some builds prefix an address. Named Lua
      // hooks do the in-process remap; this is the retry backup.
      var entered = false
      var addr = ""
      if (parts.length >= 2) {
        entered = String(parts[parts.length - 1] || "") === "1"
        addr = String(parts[0] || "")
        if (addr === "0" || addr === "1")
          addr = ""
      } else {
        entered = String(parts[0] || "") === "1"
      }
      if (root.clamshell && entered) {
        root.hideBarForFullscreen()
        var argv = [root.script, "constrain-fullscreen"]
        if (addr.indexOf("0x") === 0)
          argv.push(addr)
        fsProc.command = argv
        fsProc.running = true
        fsRetry.left = 2
        fsRetry.restart()
      }
    } else if (name === "openlayer" || name === "createlayer") {
      root.requestOverlayConstrain()
    }
  }

  onClamshellChanged: root.requestOverlayConstrain()
  onCoverRatioChanged: root.requestOverlayConstrain()
  onOverlapPxChanged: root.requestOverlayConstrain()

  Timer {
    id: restoreTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (root.screensaverOpen() || applyProc.running)
        return
      applyProc.running = true
    }
  }

  Timer {
    id: ssArmTimer
    interval: 700
    repeat: false
    onTriggered: {
      root.ssDismissArmed = root.screensaverOpen()
      root.ssSawIdle = ssIdle.isIdle === true
    }
  }

  IdleMonitor {
    id: ssIdle
    enabled: root.clamshell && root.screensaverOpen() && root.ssDismissArmed
    timeout: 1
    respectInhibitors: false
    onIsIdleChanged: {
      if (isIdle) {
        root.ssSawIdle = true
        return
      }
      if (root.ssSawIdle && root.ssDismissArmed)
        root.dismissScreensaver()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Component.onCompleted: {
    startDaemon()
    applyProc.running = true
    root.requestOverlayConstrain()
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

    function usableArea(): string {
      var w = 0
      var h = 0
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        var sc = screens[i]
        if (String(sc.name || "").indexOf("eDP") === 0) {
          w = sc.width
          h = sc.height
          break
        }
      }
      var inset = root.reservedLogical
      return JSON.stringify({
        clamshell: root.clamshell,
        insetBottom: inset,
        width: w,
        height: Math.max(0, h - inset)
      })
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
      aboveWindows: true
    }
  }
}
