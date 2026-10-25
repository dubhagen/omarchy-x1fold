# Clamshell overlay insets

Omarchy 4.0.3 sandboxes the `shell` object injected into third-party
plugins, so `mattd.x1fold` cannot walk host overlay PanelWindows and
shrink them. The Omarchy way to customize those overlays is to clone
them, then inset their own surfaces.

`setup.sh` clones (once) and patches:

| Source                 | Clone                  | Entry              |
|------------------------|------------------------|--------------------|
| `omarchy.menu`         | `mattd.menu`           | `Menu.qml`         |
| `omarchy.image-picker` | `mattd.image-picker`   | `ImagePicker.qml`  |
| `omarchy.osd`          | `mattd.osd`            | `Osd.qml`          |
| `omarchy.clipboard`    | `mattd.clipboard`      | `Clipboard.qml`    |
| `omarchy.emojis`       | `mattd.emojis`         | `Emojis.qml`       |

Each clone gets `ClamshellBounds.qml` and a marked PanelWindow change:
fill the output in tablet mode; top-anchor to the visible OLED half in
clamshell. The shell keeps routing `omarchy.menu` / `image-selector` /
`osd` IPC to the enabled clone.

`Menu.qml` fills Apps from `DesktopEntries` when
`shell.appLibrary.sortedEntries()` returns rows whose `entry` objects
were dropped by the plugin proxy. It still honors
`default/omarchy/launcher.hides` and `NoDisplay`. The shell proxy is
used when its rows still carry entry ids. The clone also refers to the
`Color` singleton directly, matching the other overlay clones' `qs.Commons`
import.

The theme wallpaper stays a click-through Bottom layer in
`mattd.x1fold` (`mattd-x1fold-wallpaper`). Hyprland keeps Background
layer surfaces full-output even with margins.

Uninstalling the fold plugin leaves these clones installed, the same
way it leaves `mattd.power`. With no `state.json` clamshell flag the
insets stay inactive. The menu clone still lists Apps from desktop
entries.
