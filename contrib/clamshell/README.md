# Clamshell overlay insets

Omarchy 4.5 sizes the stock overlays to the full Quickshell screen. There is
no usable-area hint that would inset them, so `dubhagen.x1fold` keeps its own
copies and insets those surfaces.

`setup.sh` refreshes these publisher-owned clones from the current built-in
on every run, then applies only the inset. The ids are the publisher’s, so
the install does not take a clone in the user’s own namespace. `omarchy
plugin clone` is not used: that command always names the copy after the unix
user.

| Source                 | Clone                      | Entry              |
|------------------------|----------------------------|--------------------|
| `omarchy.menu`         | `dubhagen.menu`            | `Menu.qml`         |
| `omarchy.image-picker` | `dubhagen.image-picker`    | `ImagePicker.qml`  |
| `omarchy.osd`          | `dubhagen.osd`             | `Osd.qml`          |
| `omarchy.clipboard`    | `dubhagen.clipboard`       | `Clipboard.qml`    |
| `omarchy.emojis`       | `dubhagen.emojis`          | `Emojis.qml`       |

Each clone gets `ClamshellBounds.qml` and a `.x1fold-clone` marker. Omarchy
4.5 draws these overlays with `OverlayWindow`, which stays blank until the
window is the full screen, so the patch swaps in `ClamshellOverlay` and sets
`insetBottom` from x1fold state. Tablet mode keeps a full-screen surface.
Clamshell top-anchors it to the visible OLED half. The shell keeps routing
`omarchy.menu` / `image-selector` / `osd` IPC to the enabled clone.

`Menu.qml` fills Apps from `DesktopEntries` when
`shell.appLibrary.sortedEntries()` returns rows whose `entry` objects
were dropped by the plugin proxy. It still honors
`default/omarchy/launcher.hides` and `NoDisplay`. The shell proxy is
used when its rows still carry entry ids. Colors and translations stay
on `Commons`, the same as the stock overlay.

The theme wallpaper stays a click-through Bottom layer in
`dubhagen.x1fold` (`dubhagen-x1fold-wallpaper`). Hyprland keeps Background
layer surfaces full-output even with margins.

An older installer-owned copy of the same built-in (one that still has
`ClamshellBounds.qml`, `bin/battery-status`, or `.x1fold-clone`) is disabled
and removed. A personal clone without those markers is left alone. The next
`./setup.sh` overwrites `~/.config/omarchy/plugins/dubhagen.*`.

Uninstalling the fold plugin leaves these clones installed, the same way it
leaves `dubhagen.power`. With no `state.json` clamshell flag the insets stay
inactive. The menu clone still lists Apps from desktop entries.
