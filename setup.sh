#!/usr/bin/env bash
# Install the X1 Fold Omarchy plugin from this checkout.
set -euo pipefail

PLUGIN_ID="mattd.x1fold"
POWER_ID="mattd.power"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
POWER_LIVE="${HOME}/.config/omarchy/plugins/${POWER_ID}"
BIN_LINK="${HOME}/.local/bin/x1fold"
HYPR="${HOME}/.config/hypr"
MENU="${HOME}/.config/omarchy/extensions/omarchy-menu.jsonc"
MARK_BEGIN="-- mattd.x1fold: begin"
MARK_END="-- mattd.x1fold: end"
BOOT=0
UNINSTALL=0
RESTART_SHELL=1
WVKBD_VERSION="0.20"
WVKBD_BIN="${HOME}/.local/bin/wvkbd-deskintl"
WVKBD_URL="https://github.com/jjsullivan5196/wvkbd/archive/refs/tags/v${WVKBD_VERSION}.tar.gz"

usage() {
  cat <<EOF
Install the ThinkPad X1 Fold 16 plugin into Omarchy.

Usage: ./setup.sh [options]

  --boot              Also install the Bluetooth-at-LUKS initramfs hook
                      and folio-keyboard disable-while-typing (needs sudo
                      in a terminal)
  --uninstall         Remove the plugin symlink, keybindings, menu entries,
                      and CLI link. Does not delete this checkout.
  --no-shell-restart  Skip \`omarchy restart shell\`
  -h, --help          Show this help

Default install:
  symlink this repo → ~/.config/omarchy/plugins/${PLUGIN_ID}
  enable the bar widget, keybindings, on-screen keyboard, layer rules, menu
  clone Omarchy overlays so clamshell insets the launcher, background
  switcher, OSD, clipboard, and emoji picker
EOF
}

log() { printf '==> %s\n' "$*"; }
warn() { printf 'setup.sh: %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

while (( $# > 0 )); do
  case "$1" in
    --boot) BOOT=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --no-shell-restart) RESTART_SHELL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

need_tty_sudo() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "sudo needs a terminal. Run this in a terminal: $REPO/setup.sh --boot"
  fi
  sudo -v
}

patch_marked_lua() {
  local file="$1" snippet="$2"
  python3 - "$file" "$snippet" "$MARK_BEGIN" "$MARK_END" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
snippet = pathlib.Path(sys.argv[2]).read_text()
begin, end = sys.argv[3], sys.argv[4]
block = f"{begin}\n{snippet.rstrip()}\n{end}\n"
text = path.read_text() if path.exists() else ""

# Drop an older unmarked copy of the same snippet if we are about to wrap it.
for needle in (
    'local x1fold = os.getenv("HOME") .. "/.config/omarchy/plugins/mattd.x1fold/bin/x1fold"',
    'o.launch_on_start("squeekboard")',
    'o.launch_on_start("env -u GDK_SCALE -u GDK_DPI_SCALE squeekboard")',
    'namespace = "mattd-x1fold-mask"',
    'hl.env("SQUEEKBOARD_FORCE", "1")',
):
    if begin in text:
        break
    if needle not in text:
        continue
    lines = text.splitlines(keepends=True)
    drop = []
    for i, line in enumerate(lines):
        if needle in line:
            start = i
            while start > 0 and lines[start - 1].lstrip().startswith("--"):
                start -= 1
            stop = i + 1
            while stop < len(lines) and (
                "x1fold" in lines[stop]
                or "squeekboard" in lines[stop]
                or "SQUEEKBOARD_FORCE" in lines[stop]
                or "mattd-x1fold-mask" in lines[stop]
            ):
                stop += 1
            drop.append((start, stop))
    for start, stop in reversed(drop):
        del lines[start:stop]
    text = "".join(lines)

if begin in text and end in text:
    text = re.sub(
        re.escape(begin) + r".*?" + re.escape(end) + r"\n?",
        block,
        text,
        count=1,
        flags=re.S,
    )
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text = text.rstrip() + "\n\n" + block

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
PY
}

strip_marked_lua() {
  local file="$1"
  [[ -f $file ]] || return 0
  python3 - "$file" "$MARK_BEGIN" "$MARK_END" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
begin, end = sys.argv[2], sys.argv[3]
text = path.read_text()
text = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
path.write_text(text)
PY
}

merge_menu() {
  local file="$1"
  python3 - "$file" "$REPO/contrib/omarchy-menu.jsonc" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
fragment = pathlib.Path(sys.argv[2]).read_text().rstrip()
path.parent.mkdir(parents=True, exist_ok=True)
if not path.exists():
    path.write_text("{\n" + fragment + "\n}\n")
    raise SystemExit(0)

text = path.read_text()
# Drop any previous x1fold menu keys, then insert a fresh block.
text = re.sub(
    r'\n  "trigger\.hardware\.x1fold[^"]*"\s*:\s*\{.*?\},?',
    "",
    text,
    flags=re.S,
)
if not text.rstrip().endswith("}"):
    raise SystemExit(f"setup.sh: cannot patch {path}: missing closing brace")
head, _, _ = text.rstrip().rpartition("}")
head = head.rstrip()
if head.endswith("{") or head.rstrip().endswith(","):
    pass
elif re.search(r'"\s*:\s*\{.*\}\s*$', head, flags=re.S):
    head = head + ","
path.write_text(head + "\n" + fragment + "\n}\n")
PY
}

strip_menu() {
  local file="$1"
  [[ -f $file ]] || return 0
  python3 - "$file" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = re.sub(
    r',\n  "trigger\.hardware\.x1fold".*?(?=\n\}|\n  ")',
    "",
    text,
    count=1,
    flags=re.S,
)
text = re.sub(
    r'\n  "trigger\.hardware\.x1fold".*?(?=\n\}|\n  ")',
    "",
    text,
    count=1,
    flags=re.S,
)
path.write_text(text)
PY
}

install_plugin_link() {
  mkdir -p "$(dirname "$LIVE")" "${HOME}/.local/bin"
  if [[ -L $LIVE ]]; then
    local current
    current="$(readlink -f "$LIVE")"
    if [[ $current == "$(readlink -f "$REPO")" ]]; then
      log "plugin already linked at $LIVE"
    else
      log "replacing existing symlink $LIVE"
      ln -sfn "$REPO" "$LIVE"
    fi
  elif [[ -d $LIVE ]]; then
    local backup
    backup="${HOME}/.local/share/x1fold-plugin/live-backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$(dirname "$backup")"
    log "moving existing plugin dir aside → $backup"
    mv "$LIVE" "$backup"
    ln -sfn "$REPO" "$LIVE"
  elif [[ -e $LIVE ]]; then
    die "$LIVE exists and is not a directory or symlink"
  else
    ln -sfn "$REPO" "$LIVE"
  fi
  ln -sfn "$LIVE/bin/x1fold" "$BIN_LINK"
  log "CLI → $BIN_LINK"
}

enable_plugin() {
  command -v omarchy >/dev/null || die "omarchy is not on PATH"
  if omarchy plugin list --json 2>/dev/null | grep -q "\"id\": \"${PLUGIN_ID}\""; then
    :
  else
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  if omarchy plugin list --json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
raise SystemExit(0 if any(p.get('id')=='${PLUGIN_ID}' and p.get('enabled') for p in data) else 1)
" 2>/dev/null; then
    log "plugin ${PLUGIN_ID} already enabled"
    return 0
  fi
  log "enabling ${PLUGIN_ID} on the right of the bar"
  omarchy plugin enable "$PLUGIN_ID" --section right
}

install_power_overlay() {
  # Dual-battery totals live in a cloned omarchy.power widget, not in
  # mattd.x1fold. setup.sh clones it once, then overlays our files.
  if [[ ! -d $POWER_LIVE ]]; then
    log "cloning omarchy.power → ${POWER_ID}"
    omarchy plugin clone omarchy.power
  fi
  [[ -d $POWER_LIVE ]] || die "failed to create ${POWER_LIVE}"
  mkdir -p "$POWER_LIVE/bin"
  install -m 644 "$REPO/contrib/power/Panel.qml" "$POWER_LIVE/Panel.qml"
  install -m 644 "$REPO/contrib/power/Model.js" "$POWER_LIVE/Model.js"
  install -m 755 "$REPO/contrib/power/bin/battery-status" "$POWER_LIVE/bin/battery-status"
  log "dual-battery overlay installed on ${POWER_ID} (separate from ${PLUGIN_ID})"
}

clone_id_for() {
  local source_id="$1"
  printf '%s.%s' "${USER:-$(id -un)}" "${source_id#omarchy.}"
}

install_overlay_clone() {
  # Omarchy 4.0.3 sandboxes third-party overlay discovery. Clone the
  # first-party overlay and inset its own PanelWindow from x1fold state.
  local source_id="$1" entry="$2"
  local clone_id clone_dir
  clone_id="$(clone_id_for "$source_id")"
  clone_dir="${HOME}/.config/omarchy/plugins/${clone_id}"
  if [[ ! -d $clone_dir ]]; then
    log "cloning ${source_id} → ${clone_id}"
    omarchy plugin clone "$source_id"
  fi
  [[ -d $clone_dir ]] || die "failed to create ${clone_dir}"
  python3 "$REPO/contrib/clamshell/patch.py" apply "$clone_dir" "$entry"
  log "clamshell inset on ${clone_id} (${entry})"
}

install_overlay_clones() {
  install_overlay_clone omarchy.menu Menu.qml
  install_overlay_clone omarchy.image-picker ImagePicker.qml
  install_overlay_clone omarchy.osd Osd.qml
  install_overlay_clone omarchy.clipboard Clipboard.qml
  install_overlay_clone omarchy.emojis Emojis.qml
}

install_wvkbd() {
  mkdir -p "${HOME}/.local/bin"
  if [[ -x $WVKBD_BIN ]]; then
    log "on-screen keyboard already at $WVKBD_BIN"
    return 0
  fi
  command -v make >/dev/null || die "make is required to build the on-screen keyboard"
  command -v pkg-config >/dev/null || die "pkg-config is required to build the on-screen keyboard"
  command -v wayland-scanner >/dev/null || die "wayland-scanner is required to build the on-screen keyboard"
  local missing=() pkg
  for pkg in wayland-client xkbcommon pangocairo; do
    pkg-config --exists "$pkg" || missing+=("$pkg")
  done
  if (( ${#missing[@]} )); then
    die "missing pkg-config packages for the on-screen keyboard: ${missing[*]}
Install: pacman -S --needed base-devel wayland pango cairo libxkbcommon"
  fi
  local fetch=""
  if command -v curl >/dev/null; then
    fetch="curl"
  elif command -v wget >/dev/null; then
    fetch="wget"
  else
    die "curl or wget is required to fetch wvkbd"
  fi
  local work src
  work="$(mktemp -d)"
  src="$work/wvkbd-${WVKBD_VERSION}"
  log "building wvkbd-deskintl ${WVKBD_VERSION}"
  if [[ $fetch == curl ]]; then
    curl -fsSL "$WVKBD_URL" | tar -xz -C "$work"
  else
    wget -qO- "$WVKBD_URL" | tar -xz -C "$work"
  fi
  [[ -d $src ]] || die "wvkbd source did not unpack at $src"
  if ! make -C "$src" LAYOUT=deskintl wvkbd-deskintl; then
    rm -rf "$work"
    die "failed to build wvkbd-deskintl"
  fi
  install -m 755 "$src/wvkbd-deskintl" "$WVKBD_BIN"
  rm -rf "$work"
  log "on-screen keyboard → $WVKBD_BIN"
}

strip_gtk_css_block() {
  local file="${HOME}/.config/gtk-3.0/gtk.css"
  [[ -f $file ]] || return 0
  python3 - "$file" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
updated = re.sub(
    r"\n?/\* mattd\.x1fold squeekboard \*/.*?/\* mattd\.x1fold squeekboard end \*/\n?",
    "\n",
    text,
    count=1,
    flags=re.S,
)
if updated != text:
    path.write_text(updated)
PY
}

install_desktop() {
  mkdir -p "$HYPR" "$(dirname "$MENU")"
  patch_marked_lua "$HYPR/bindings.lua" "$REPO/contrib/bindings.lua"
  patch_marked_lua "$HYPR/autostart.lua" "$REPO/contrib/autostart.lua"
  patch_marked_lua "$HYPR/hyprland.lua" "$REPO/contrib/hyprland.lua"
  patch_marked_lua "$HYPR/input.lua" "$REPO/contrib/input.lua"
  mkdir -p "${HOME}/.config/libinput"
  install -m 644 "$REPO/contrib/libinput-x1fold.quirks" "${HOME}/.config/libinput/local-overrides.quirks"
  strip_gtk_css_block
  merge_menu "$MENU"
  log "Hyprland bindings, autostart, layer rules, keyboard input, and menu entries installed"
}

install_boot() {
  need_tty_sudo
  log "installing bluetoothkbd initramfs hook"
  sudo mkdir -p /etc/initcpio/install /etc/initcpio/hooks /etc/mkinitcpio.conf.d
  sudo install -m 755 "$REPO/initcpio/install/bluetoothkbd" /etc/initcpio/install/bluetoothkbd
  sudo install -m 755 "$REPO/initcpio/hooks/bluetoothkbd" /etc/initcpio/hooks/bluetoothkbd
  sudo install -m 755 "$REPO/initcpio/install/bluetoothkbd-stop" /etc/initcpio/install/bluetoothkbd-stop
  sudo install -m 755 "$REPO/initcpio/hooks/bluetoothkbd-stop" /etc/initcpio/hooks/bluetoothkbd-stop
  sudo install -m 644 "$REPO/initcpio/zz-x1fold-bluetooth.conf" /etc/mkinitcpio.conf.d/zz-x1fold-bluetooth.conf
  sudo mkdir -p /etc/libinput /etc/udev/hwdb.d /etc/udev/rules.d
  sudo install -m 644 "$REPO/contrib/libinput-x1fold.quirks" /etc/libinput/local-overrides.quirks
  sudo install -m 644 "$REPO/contrib/udev-x1fold-touchpad.hwdb" /etc/udev/hwdb.d/71-x1fold-touchpad.hwdb
  sudo install -m 644 "$REPO/contrib/udev-x1fold-keyboard.rules" /etc/udev/rules.d/66-x1fold-keyboard.rules
  sudo mkdir -p /usr/local/lib/x1fold /etc/systemd/system
  sudo install -m 755 "$REPO/contrib/rebind-cnvi-bt" /usr/local/lib/x1fold/rebind-cnvi-bt
  sudo install -m 644 "$REPO/contrib/x1fold-rebind-bluetooth.service" /etc/systemd/system/x1fold-rebind-bluetooth.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now x1fold-rebind-bluetooth.service
  sudo systemd-hwdb update
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=input --action=add || true
  if [[ -f /etc/bluetooth/main.conf ]]; then
    sudo sed -i 's/^#AutoEnable=true/AutoEnable=true/' /etc/bluetooth/main.conf
  fi
  log "rebuilding initramfs"
  if command -v limine-mkinitcpio >/dev/null; then
    sudo limine-mkinitcpio
  else
    sudo mkinitcpio -P
  fi
  log "Bluetooth keyboard hook installed. Reboot to use it at the LUKS prompt."
}

do_uninstall() {
  log "removing desktop integration"
  pkill -x wvkbd-deskintl >/dev/null 2>&1 || true
  strip_marked_lua "$HYPR/bindings.lua"
  strip_marked_lua "$HYPR/autostart.lua"
  strip_marked_lua "$HYPR/hyprland.lua"
  strip_marked_lua "$HYPR/input.lua"
  strip_menu "$MENU"
  strip_gtk_css_block
  if [[ -L $BIN_LINK ]]; then
    rm -f "$BIN_LINK"
  fi
  if [[ -f $WVKBD_BIN ]]; then
    rm -f "$WVKBD_BIN"
    log "removed $WVKBD_BIN"
  fi
  if command -v omarchy >/dev/null; then
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  if [[ -L $LIVE ]]; then
    rm -f "$LIVE"
    log "removed symlink $LIVE"
  fi
  if (( RESTART_SHELL )) && command -v omarchy >/dev/null; then
    omarchy restart shell
  fi
  log "checkout left at $REPO"
}

[[ -f $REPO/manifest.json ]] || die "manifest.json missing; run from the repo root"
command -v python3 >/dev/null || die "python3 is required"

if (( UNINSTALL )); then
  do_uninstall
  exit 0
fi

log "installing ${PLUGIN_ID} from $REPO"
install_plugin_link
install_wvkbd
install_desktop
enable_plugin
install_power_overlay
install_overlay_clones

if (( BOOT )); then
  install_boot
fi

if (( RESTART_SHELL )); then
  log "restarting Omarchy shell"
  omarchy restart shell
fi

log "done. Left-click the fold icon on the bar, or run: x1fold status"
if (( ! BOOT )); then
  printf '\n    Bluetooth keyboard at LUKS:  ./setup.sh --boot\n\n'
fi
