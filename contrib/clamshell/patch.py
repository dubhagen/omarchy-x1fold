#!/usr/bin/env python3
"""Copy ClamshellBounds.qml into a cloned Omarchy overlay and inset its PanelWindow."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

BOUNDS_MARK_BEGIN = "  // mattd.x1fold: clamshell-bounds"
BOUNDS_MARK_END = "  // mattd.x1fold: clamshell-bounds end"
ANCHOR_MARK_BEGIN = "    // mattd.x1fold: clamshell-anchors"
ANCHOR_MARK_END = "    // mattd.x1fold: clamshell-anchors end"
STOCK_ANCHORS = "    anchors { top: true; bottom: true; left: true; right: true }"
CLAMSHELL_ANCHORS = """    // mattd.x1fold: clamshell-anchors
    anchors { top: true; left: true; right: true; bottom: !x1foldBounds.activeOn(screen) }
    implicitHeight: x1foldBounds.activeOn(screen) ? x1foldBounds.usableHeightFor(screen) : 0
    // mattd.x1fold: clamshell-anchors end"""
BOUNDS_BLOCK = """  // mattd.x1fold: clamshell-bounds
  ClamshellBounds { id: x1foldBounds }
  // mattd.x1fold: clamshell-bounds end
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
    if ANCHOR_MARK_BEGIN in text:
        return text
    if STOCK_ANCHORS not in text:
        fail("could not find stock PanelWindow fill anchors")
    return text.replace(STOCK_ANCHORS, CLAMSHELL_ANCHORS, 1)


def unpatch(text: str) -> str:
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
    return text


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"apply", "revert"}:
        fail("usage: patch.py apply|revert <clone-dir> <entry.qml>")
    action, clone_dir, entry_name = argv[1], Path(argv[2]), argv[3]
    here = Path(__file__).resolve().parent
    bounds_src = here / "ClamshellBounds.qml"
    entry = clone_dir / entry_name
    bounds_dst = clone_dir / "ClamshellBounds.qml"
    if not clone_dir.is_dir():
        fail(f"clone directory missing: {clone_dir}")
    if not entry.is_file():
        fail(f"entry point missing: {entry}")

    if action == "revert":
        text = unpatch(entry.read_text())
        entry.write_text(text)
        bounds_dst.unlink(missing_ok=True)
        return 0

    if not bounds_src.is_file():
        fail(f"missing {bounds_src}")
    shutil.copy2(bounds_src, bounds_dst)
    text = replace_anchors(insert_bounds(entry.read_text()))
    entry.write_text(text)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except KeyboardInterrupt:
        raise SystemExit(130)
