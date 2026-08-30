import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "mattd.x1fold"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string script: pluginDir + "/bin/x1fold"
  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy/x1fold/state.json"

  property bool clamshell: false
  property string statusLabel: "X1 Fold"
  property string statusIcon: "󰹑"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string glyph: root.statusIcon
  readonly property string tip: {
    var label = root.statusLabel || "X1 Fold"
    if (root.clamshell)
      return label + " · Clamshell"
    return label
  }

  function applyStateText(text) {
    try {
      var data = JSON.parse(text || "{}")
      root.clamshell = data.clamshell === true
      var transform = Number(data.transform || 0)
      var portrait = (transform % 2) === 0
      if (data.label)
        root.statusLabel = data.label
      else if (portrait)
        root.statusLabel = transform === 2 ? "Portrait (flipped)" : "Portrait"
      else
        root.statusLabel = transform === 1 ? "Landscape (flipped)" : "Landscape"
      root.statusIcon = root.clamshell ? "󰌌" : (portrait ? "󰁞" : "󰹑")
    } catch (e) {}
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStateText(text())
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      Qt.callLater(root.refresh)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    slotSize: Style.bar.statusSlot
    tooltipText: root.tip
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run(root.script + " clamshell toggle")
      else if (b === Qt.MiddleButton) root.bar.run(root.script + " rotate cycle")
      else root.togglePanel()
    }
  }
}
