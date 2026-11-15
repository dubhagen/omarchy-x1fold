#!/usr/bin/env python3
"""Patch a cloned Omarchy overlay.

Every overlay gets ClamshellBounds. Omarchy 4.5 overlays are OverlayWindow,
which stays blank until its height matches the screen, so the inset is a
ClamshellOverlay with insetBottom. Older PanelWindow clones keep the fill
anchors they already have. Menu.qml also gets an Apps-list fallback: the
shell's plugin app-library proxy drops desktop-entry objects, so a stock
merge leaves Apps empty. The dock clone is not a first-party service, so
Dock.qml also gets DockShell: shell.json pin inheritance and desktop entries.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

BOUNDS_MARK_BEGIN = "  // dubhagen.x1fold: clamshell-bounds"
BOUNDS_MARK_END = "  // dubhagen.x1fold: clamshell-bounds end"
ANCHOR_MARK_BEGIN = "    // dubhagen.x1fold: clamshell-anchors"
ANCHOR_MARK_END = "    // dubhagen.x1fold: clamshell-anchors end"
OVERLAY_MARK_BEGIN = "    // dubhagen.x1fold: clamshell-overlay"
OVERLAY_MARK_END = "    // dubhagen.x1fold: clamshell-overlay end"
OVERLAY_BLOCK = """    // dubhagen.x1fold: clamshell-overlay
    insetBottom: x1foldBounds.activeOn(screen) ? x1foldBounds.insetFor(screen) : 0
    // dubhagen.x1fold: clamshell-overlay end
"""
STOCK_ANCHORS = "    anchors { top: true; bottom: true; left: true; right: true }"
CLAMSHELL_ANCHORS = """    // dubhagen.x1fold: clamshell-anchors
    anchors { top: true; left: true; right: true; bottom: !x1foldBounds.activeOn(screen) }
    implicitHeight: x1foldBounds.activeOn(screen) ? x1foldBounds.usableHeightFor(screen) : 0
    // dubhagen.x1fold: clamshell-anchors end"""
BOUNDS_BLOCK = """  // dubhagen.x1fold: clamshell-bounds
  ClamshellBounds { id: x1foldBounds }
  // dubhagen.x1fold: clamshell-bounds end
"""
MENU_APPS_MARK = "A cloned menu only sees AppLibrary through the plugin proxy."
HIDDEN_BLOCK = """  // Ids from the stock launcher hide list. The cloned menu reads desktop
  // entries itself when the shell's app-library proxy returns no usable rows.
  property var hiddenLauncherIds: ({})

"""
STOCK_APPS = """  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        searchTerms: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }
"""
NEW_APPS = """  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  //
  // A cloned menu only sees AppLibrary through the plugin proxy. That proxy
  // drops the desktop-entry objects inside the returned rows, which leaves
  // Apps on "Nothing here yet" even when applications are installed. When the
  // proxy rows are unusable, read DesktopEntries in this plugin instead.
  function libraryAppRows() {
    if (!root.appLibrary) return null
    try {
      var rows = root.appLibrary.sortedEntries("")
      if (!rows || !rows.length || !rows[0] || !rows[0].entry || !rows[0].entry.id) return null
      return rows
    } catch (e) {
      return null
    }
  }

  function desktopAppRows() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return [] }
    var hidden = root.hiddenLauncherIds || ({})
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var id = String(entry.id || "")
      if (!id || hidden[id]) continue
      if (!String(entry.name || "")) continue
      rows.push({ entry: entry })
    }
    rows.sort(function(a, b) {
      var aName = String(a.entry.name || "").toLowerCase()
      var bName = String(b.entry.name || "").toLowerCase()
      if (aName < bName) return -1
      if (aName > bName) return 1
      var aId = String(a.entry.id || "")
      var bId = String(b.entry.id || "")
      if (aId < bId) return -1
      if (aId > bId) return 1
      return 0
    })
    return rows
  }

  function loadHiddenLaunchers(raw) {
    var next = ({})
    var lines = String(raw || "").split("\\n")
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id.length > 0) next[id] = true
    }
    root.hiddenLauncherIds = next
    if (root.providersLoaded["apps"]) root.mergeAppRows()
  }

  function appLabel(entry) {
    var name = String(entry.name || "")
    if (name) return name
    if (!root.appLibrary) return String(entry.id || "")
    try { return String(root.appLibrary.entryName(entry) || entry.id || "") } catch (e) { return String(entry.id || "") }
  }

  function appSubtext(entry) {
    var text = String(entry.genericName || "")
    if (text || !root.appLibrary) return text
    try { return String(root.appLibrary.entrySubtext(entry) || "") } catch (e) { return "" }
  }

  function mergeAppRows() {
    var rows = root.libraryAppRows()
    if (!rows) rows = root.desktopAppRows()

    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      if (!entry) continue
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appSubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLabel(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        searchTerms: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }
"""
WATCH_BLOCK = """  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  FileView {
    id: launcherHidesFile
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadHiddenLaunchers(text())
    onFileChanged: reload()
  }

"""
JSONC_NEEDLE = "  // The JSONC sources are watched so live edits to the default file (or the\n"
DOCK_MARK = "dubhagen.x1fold: dock-shell"
DOCK_STOCK = """  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var dockConfig: shell && shell.shellConfig && shell.shellConfig.dock ? shell.shellConfig.dock : ({})
  readonly property var defaultDockConfig: shell && shell.defaultsConfig && shell.defaultsConfig.dock ? shell.defaultsConfig.dock : ({})
"""
DOCK_PATCH = """  // dubhagen.x1fold: dock-shell
  // A cloned dock is not first-party, so its shell has no config and no app
  // library. DockShell reads shell.json and the desktop entries instead.
  DockShell { id: x1foldDockShell }
  readonly property var appLibrary: {
    var host = null
    try { if (shell) host = shell.appLibrary } catch (e) { host = null }
    return host || x1foldDockShell
  }
  readonly property var dockConfig: {
    var host = null
    try { if (shell && shell.shellConfig) host = shell.shellConfig.dock } catch (e) { host = null }
    return host || x1foldDockShell.userDock
  }
  readonly property var defaultDockConfig: {
    var host = null
    try { if (shell && shell.defaultsConfig) host = shell.defaultsConfig.dock } catch (e) { host = null }
    return host || x1foldDockShell.defaultDock
  }
  // dubhagen.x1fold: dock-shell end
"""


def fail(msg: str) -> None:
    print(f"clamshell-patch: {msg}", file=sys.stderr)
    raise SystemExit(1)


def insert_bounds(text: str) -> str:
    if BOUNDS_MARK_BEGIN in text:
        return text
    needle = "  id: root\n"
    if needle not in text:
        fail("could not find `id: root` to insert ClamshellBounds")
    return text.replace(needle, needle + "\n" + BOUNDS_BLOCK, 1)


def replace_anchors(text: str) -> str:
    if ANCHOR_MARK_BEGIN in text or OVERLAY_MARK_BEGIN in text or "ClamshellOverlay {" in text:
        return text
    overlay = "  OverlayWindow {"
    if overlay in text:
        return text.replace(
            overlay,
            "  ClamshellOverlay {\n" + OVERLAY_BLOCK.rstrip("\n"),
            1,
        )
    if STOCK_ANCHORS not in text:
        fail("could not find OverlayWindow or stock PanelWindow fill anchors")
    return text.replace(STOCK_ANCHORS, CLAMSHELL_ANCHORS, 1)


def patch_menu_colors(text: str) -> str:
    text = text.replace("import qs.Commons as Commons\n", "", 1)
    return text.replace("Commons.Color", "Color")


def unpatch_menu_colors(text: str) -> str:
    if "import qs.Commons as Commons\n" not in text:
        text = text.replace(
            "import qs.Commons\n",
            "import qs.Commons\nimport qs.Commons as Commons\n",
            1,
        )
    text = text.replace("via Color.qml", "via Commons.Color.qml")
    return text.replace("Color.menu", "Commons.Color.menu")


def patch_menu_apps(text: str) -> str:
    if MENU_APPS_MARK in text:
        return text
    revision = "  property int providerRevision: 0\n\n"
    if revision not in text:
        fail("could not find providerRevision to insert the apps fallback")
    text = text.replace(revision, "  property int providerRevision: 0\n" + HIDDEN_BLOCK, 1)
    if STOCK_APPS not in text:
        fail("could not find stock mergeAppRows() to install the apps fallback")
    text = text.replace(STOCK_APPS, NEW_APPS, 1)
    if JSONC_NEEDLE not in text:
        fail("could not find the menu JSONC watcher to insert the apps refresh")
    return text.replace(JSONC_NEEDLE, WATCH_BLOCK + JSONC_NEEDLE, 1)


def unpatch_menu_apps(text: str) -> str:
    if MENU_APPS_MARK not in text:
        return text
    if NEW_APPS not in text:
        fail("menu apps fallback is present but mergeAppRows() does not match; refusing to revert")
    text = text.replace(NEW_APPS, STOCK_APPS, 1)
    if HIDDEN_BLOCK not in text:
        fail("menu apps fallback is present but hiddenLauncherIds does not match; refusing to revert")
    text = text.replace(HIDDEN_BLOCK, "\n", 1)
    if WATCH_BLOCK not in text:
        fail("menu apps fallback is present but the desktop-entry watcher does not match; refusing to revert")
    text = text.replace(WATCH_BLOCK, "", 1)
    if "Color.menu" in text and "import qs.Commons as Commons\n" not in text:
        text = unpatch_menu_colors(text)
    return text


def patch_dock(clone_dir: Path, here: Path) -> None:
    dock = clone_dir / "Dock.qml"
    shell_src = here / "DockShell.qml"
    search_src = here / "DockAppSearch.js"
    if not dock.is_file():
        fail(f"entry point missing: {dock}")
    if not shell_src.is_file() or not search_src.is_file():
        fail("missing DockShell.qml or DockAppSearch.js")
    text = dock.read_text()
    if DOCK_MARK not in text:
        if DOCK_STOCK not in text:
            fail("could not find the dock shell properties in Dock.qml")
        text = text.replace(DOCK_STOCK, DOCK_PATCH, 1)
        dock.write_text(text)
    shutil.copy2(shell_src, clone_dir / "DockShell.qml")
    shutil.copy2(search_src, clone_dir / "DockAppSearch.js")


def unpatch_dock(clone_dir: Path) -> None:
    dock = clone_dir / "Dock.qml"
    if dock.is_file():
        text = dock.read_text()
        if DOCK_MARK in text:
            if DOCK_PATCH not in text:
                fail("dock shell patch is present but does not match; refusing to revert")
            dock.write_text(text.replace(DOCK_PATCH, DOCK_STOCK, 1))
    (clone_dir / "DockShell.qml").unlink(missing_ok=True)
    (clone_dir / "DockAppSearch.js").unlink(missing_ok=True)


def unpatch(text: str, entry_name: str = "") -> str:
    if OVERLAY_MARK_BEGIN in text and OVERLAY_MARK_END in text:
        start = text.index(OVERLAY_MARK_BEGIN)
        end = text.index(OVERLAY_MARK_END) + len(OVERLAY_MARK_END)
        if end < len(text) and text[end] == "\n":
            end += 1
        text = text[:start] + text[end:]
        text = text.replace("  ClamshellOverlay {", "  OverlayWindow {", 1)
    if ANCHOR_MARK_BEGIN in text and ANCHOR_MARK_END in text:
        start = text.index(ANCHOR_MARK_BEGIN)
        end = text.index(ANCHOR_MARK_END) + len(ANCHOR_MARK_END)
        if end < len(text) and text[end] == "\n":
            end += 1
        text = text[:start] + STOCK_ANCHORS + "\n" + text[end:]
    if BOUNDS_MARK_BEGIN in text and BOUNDS_MARK_END in text:
        start = text.index(BOUNDS_MARK_BEGIN)
        end = text.index(BOUNDS_MARK_END) + len(BOUNDS_MARK_END)
        if end < len(text) and text[end] == "\n":
            end += 1
        while start > 0 and text[start - 1] == "\n" and text[start - 2 : start] == "\n\n":
            start -= 1
        text = text[:start] + text[end:]
    if entry_name == "Menu.qml":
        text = unpatch_menu_apps(text)
    return text


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"apply", "revert"}:
        fail("usage: patch.py apply|revert <clone-dir> <entry.qml>")
    action, clone_dir, entry_name = argv[1], Path(argv[2]), argv[3]
    here = Path(__file__).resolve().parent
    bounds_src = here / "ClamshellBounds.qml"
    overlay_src = here / "ClamshellOverlay.qml"
    entry = clone_dir / entry_name
    bounds_dst = clone_dir / "ClamshellBounds.qml"
    overlay_dst = clone_dir / "ClamshellOverlay.qml"
    if not clone_dir.is_dir():
        fail(f"clone directory missing: {clone_dir}")
    if not entry.is_file():
        fail(f"entry point missing: {entry}")

    if action == "revert":
        text = unpatch(entry.read_text(), entry_name)
        entry.write_text(text)
        bounds_dst.unlink(missing_ok=True)
        overlay_dst.unlink(missing_ok=True)
        if entry_name == "AppGrid.qml":
            unpatch_dock(clone_dir)
        return 0

    if not bounds_src.is_file():
        fail(f"missing {bounds_src}")
    if not overlay_src.is_file():
        fail(f"missing {overlay_src}")
    shutil.copy2(bounds_src, bounds_dst)
    text = insert_bounds(entry.read_text())
    if "  OverlayWindow {" in text or "  ClamshellOverlay {" in text:
        shutil.copy2(overlay_src, overlay_dst)
    text = replace_anchors(text)
    if entry_name == "Menu.qml":
        text = patch_menu_apps(text)
    if entry_name == "AppGrid.qml":
        patch_dock(clone_dir, here)
    entry.write_text(text)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except KeyboardInterrupt:
        raise SystemExit(130)
