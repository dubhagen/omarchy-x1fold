import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "mattd.x1fold"
  ipcTarget: "mattd.x1fold"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color fg: bar ? bar.foreground : Color.popups.text
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string script: pluginDir + "/bin/x1fold"

  property int orientationIndex: 3
  property bool clamshell: false
  property bool autorotate: false
  property real coverRatio: 0.5
  property int overlapPx: 0
  property bool oskOn: false
  property string statusLabel: "Landscape"
  property string statusIcon: "󰹑"
  property bool cmdBusy: false
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/x1fold/state.json"

  readonly property string orientationValue: {
    var names = { 0: "portrait", 1: "landscape-flip", 2: "portrait-flip", 3: "landscape" }
    return names[orientationIndex] || "landscape"
  }

  readonly property string modeDetail: clamshell ? "Clamshell" : "Full panel"
  readonly property string modeMeta: {
    var bits = [statusLabel]
    if (autorotate) bits.push("auto-rotate")
    if (oskOn) bits.push("on-screen keyboard")
    return bits.join(" · ")
  }

  readonly property var orientationOptions: [
    { value: "portrait", label: "Portrait", icon: "󰁞", tooltip: "Tall, camera on the short edge" },
    { value: "portrait-flip", label: "Portrait flip", icon: "󰁆", tooltip: "Tall, rotated 180°" },
    { value: "landscape", label: "Landscape", icon: "󰹑", tooltip: "Wide, the usual desk layout" },
    { value: "landscape-flip", label: "Landscape flip", icon: "󰑍", tooltip: "Wide, rotated 180°" }
  ]

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function numOr(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback
    var n = Number(value)
    return isFinite(n) ? n : fallback
  }

  function snapOverlap(value) {
    var n = Math.round(root.numOr(value, 0) / 5) * 5
    if (n > 50) n = 50
    if (n < -50) n = -50
    return n
  }

  function nudgeOverlap(delta) {
    if (root.cmdBusy) return
    root.run(["overlap", String(root.snapOverlap(root.overlapPx + delta))])
  }

  function applyStateText(text) {
    try {
      if (root.cmdBusy) return
      var data = JSON.parse(text || "{}")
      root.orientationIndex = Number(data.transform || 0)
      root.clamshell = data.clamshell === true
      root.autorotate = data.autorotate === true
      root.coverRatio = root.numOr(data.cover_ratio, 0.5)
      var sliding = false
      try { sliding = overlapSlider.dragging === true } catch (e2) {}
      if (!sliding)
        root.overlapPx = root.numOr(data.overlap_px, 0)
      root.oskOn = data.osk === true
      var portrait = (root.orientationIndex % 2) === 0
      if (data.label)
        root.statusLabel = data.label
      else if (portrait)
        root.statusLabel = root.orientationIndex === 2 ? "Portrait (flipped)" : "Portrait"
      else
        root.statusLabel = root.orientationIndex === 1 ? "Landscape (flipped)" : "Landscape"
      root.statusIcon = root.clamshell ? "󰌌" : (portrait ? "󰁞" : "󰹑")
    } catch (e) {}
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function run(args) {
    if (cmdProc.running) return false
    cmdBusy = true
    var argv = [root.script]
    for (var i = 0; i < args.length; i++) argv.push(args[i])
    cmdProc.command = argv
    cmdProc.running = true
    return true
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyStateText(text())
  }

  Process {
    id: statusProc
    command: [root.script, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (root.cmdBusy) return
          var data = JSON.parse(text)
          root.orientationIndex = Number(data.transform || 0)
          root.clamshell = data.clamshell === true
          root.autorotate = data.autorotate === true
          root.coverRatio = root.numOr(data.cover_ratio, 0.5)
          if (!overlapSlider.dragging)
            root.overlapPx = root.numOr(data.overlap_px, 0)
          root.oskOn = data.osk === true
          root.statusLabel = data.label || "X1 Fold"
          root.statusIcon = data.icon || "󰹑"
        } catch (e) {}
      }
    }
  }

  Process {
    id: cmdProc
    onExited: {
      root.cmdBusy = false
      root.refresh()
    }
  }

  Timer {
    interval: 1500
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "c" || t === "C") root.run(["clamshell", "toggle"])
        else if (t === "r" || t === "R") root.run(["rotate", "cycle"])
        else if (t === "a" || t === "A") root.run(["autorotate", "toggle"])
        else if (t === "k" || t === "K") root.run(["osk", "toggle"])
        else if (t === "t" || t === "T") root.run(["tablet"])
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(16)

        PanelHero {
          width: parent.width
          title: "X1 Fold"
          meta: root.modeMeta
          detail: ""
          foreground: root.fg
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.statusIcon
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.clamshell ? 1 : 0.9
            }
          }
          trailingControl: Component {
            Row {
              spacing: Style.space(10)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.modeDetail
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: root.clamshell
                busy: root.cmdBusy
                foreground: root.fg
                onToggled: {
                  var wanted = !root.clamshell
                  if (root.run(["clamshell", wanted ? "on" : "off"]))
                    root.clamshell = wanted
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.clamshell
            ? "Lower half is blacked out for the Bluetooth keyboard. Windows stay on the top half."
            : "Full OLED. Flip the switch to cover the lower half when the keyboard is on the glass."
          color: Qt.darker(root.fg, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.fg }

        PanelSectionHeader {
          text: "ORIENTATION"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Grid {
          id: orientGrid
          width: parent.width
          columns: 2
          columnSpacing: Style.space(6)
          rowSpacing: Style.space(6)
          Repeater {
            model: root.orientationOptions
            Button {
              required property var modelData
              width: (orientGrid.width - orientGrid.columnSpacing) / 2
              text: modelData.label
              tooltipText: modelData.tooltip
              selected: root.orientationValue === modelData.value
              bordered: true
              foreground: root.fg
              onClicked: root.run(["rotate", modelData.value])
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Auto-rotate"
          description: "Follow the accelerometers. Ignored while the screensaver is up."
          checked: root.autorotate
          foreground: root.fg
          onClicked: root.run(["autorotate", "toggle"])
        }

        PanelSeparator { foreground: root.fg }

        PanelSectionHeader {
          text: "KEYBOARD OVERLAP"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "0 is a clean half. Negative reveals more screen below the fold. Positive adds black reserved space above the keyboard."
          color: Qt.darker(root.fg, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          id: overlapRow
          width: parent.width
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(108)
            text: "Overlap  " + root.overlapPx + " px"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            id: minusBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "−"
            tooltipText: "Reveal 5 px more screen below the fold"
            bordered: true
            foreground: root.fg
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: root.nudgeOverlap(-5)
          }

          PanelSlider {
            id: overlapSlider
            width: overlapRow.width - Style.space(108) - minusBtn.width - plusBtn.width - overlapRow.spacing * 3
            anchors.verticalCenter: parent.verticalCenter
            bar: root.bar
            minimum: -50
            maximum: 50
            step: 5
            integer: true
            tickCount: 5
            value: root.overlapPx
            onMoved: function(v) { root.overlapPx = root.snapOverlap(v) }
            onReleased: function(v) { root.run(["overlap", String(root.snapOverlap(v))]) }
          }

          Button {
            id: plusBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            tooltipText: "Add 5 px of black reserved space"
            bordered: true
            foreground: root.fg
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: root.nudgeOverlap(5)
          }
        }

        PanelSeparator { foreground: root.fg }

        PanelSectionHeader {
          text: "ON-SCREEN KEYBOARD"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Item {
          width: parent.width
          implicitHeight: oskToggle.implicitHeight

          Toggle {
            id: oskToggle
            width: parent.width
            label: "On-screen keyboard"
            description: "Stays at the bottom of the screen. Windows and fullscreen use only the space above it. Super+Alt+R also toggles it."
            checked: root.oskOn
            foreground: root.fg
            onClicked: root.run(["osk", "toggle"])
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Super+R cycle · Super+Shift+R clamshell · Super+Alt+R on-screen keyboard · Super+Alt+Shift+R full panel"
          color: Qt.darker(root.fg, 1.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
