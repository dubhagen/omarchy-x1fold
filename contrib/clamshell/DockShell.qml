import QtQuick
import Quickshell
import Quickshell.Io
import "DockAppSearch.js" as AppSearch

// A cloned dock is not a first-party service, so the host gives it a scoped
// shell with no shellConfig, defaultsConfig, or appLibrary. This reads the
// same two shell.json files the dock command uses: a user pin list wins, and
// a shell.json without pins keeps the defaults. The app grid reads desktop
// entries directly, including the launcher hide list.
Item {
  id: root

  property string home: Quickshell.env("HOME")
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var userDock: ({})
  property var defaultDock: ({})
  property var configuredHiddenIds: ({})
  property var desktopHiddenIds: ({})

  signal appsChanged()

  function parseDock(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (data && data.dock && typeof data.dock === "object")
        return data.dock
    } catch (e) {}
    return ({})
  }

  function normalizeId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop")
      value = value.slice(0, -8)
    return value
  }

  function loadIdSet(raw) {
    var next = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeId(lines[i])
      if (id.length > 0)
        next[id] = true
    }
    return next
  }

  function isHidden(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenIds[id] === true || root.desktopHiddenIds[id] === true
  }

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function sortedEntries(query) {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return [] }
    return AppSearch.sortedEntries(values, query, function (entry) { return root.isHidden(entry) })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0)
      return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.charAt(0) === "/")
      return "file://" + value
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0)
      return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {}

  function terminalCommand(entry) {
    if (!entry || !entry.runInTerminal)
      return []
    return (entry.command || []).filter(function (word) { return !/^%[a-zA-Z]$/.test(String(word)) })
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id)
      return
    var entry = null
    try { entry = DesktopEntries.byId(id) } catch (e) {}
    var command = root.terminalCommand(entry)
    if (command.length > 0) {
      Util.execDetached("omarchy-launch-tui " + command.map(function (word) { return Util.shellQuote(word) }).join(" "))
      return
    }
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    name = name || ""
  }

  function remove(desktopId, name) {
    var id = String(desktopId || "")
    if (!id)
      return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id)))
  }

  function startHiddenScan() {
    if (hiddenScan.running)
      return
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function (value) {
      return String(value || "").length > 0
    }).join(":")
    hiddenScan.command = ["bash", root.omarchyPath + "/shell/services/hidden-entries.sh", desktop]
    hiddenScan.running = true
  }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.userDock = root.parseDock(text())
    onFileChanged: reload()
    onLoadFailed: root.userDock = ({})
  }

  FileView {
    path: root.omarchyPath + "/config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.defaultDock = root.parseDock(text())
    onFileChanged: reload()
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.configuredHiddenIds = root.loadIdSet(text())
      root.appsChanged()
    }
    onFileChanged: reload()
    onLoadFailed: {
      root.configuredHiddenIds = ({})
      root.appsChanged()
    }
  }

  Process {
    id: hiddenScan
    stdout: StdioCollector { id: hiddenOut; waitForEnd: true }
    onExited: {
      root.desktopHiddenIds = root.loadIdSet(hiddenOut.text)
      root.appsChanged()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.appsChanged()
      root.startHiddenScan()
    }
  }

  Component.onCompleted: root.startHiddenScan()
}
