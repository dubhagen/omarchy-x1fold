#!/usr/bin/env bash
# Install the X1 Fold Omarchy plugin from this checkout.
set -euo pipefail

PUBLISHER="dubhagen"
PLUGIN_ID="${PUBLISHER}.x1fold"
PACK_STATUS_BIN="${HOME}/.local/bin/x1fold-battery-status"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
PLUGINS_DIR="${HOME}/.config/omarchy/plugins"
BIN_LINK="${HOME}/.local/bin/x1fold"
HYPR="${HOME}/.config/hypr"
MENU="${HOME}/.config/omarchy/extensions/omarchy-menu.jsonc"
MARK_BEGIN="-- dubhagen.x1fold: begin"
MARK_END="-- dubhagen.x1fold: end"
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

  --boot              Also install the Bluetooth-at-LUKS initramfs hook,
                      folio-keyboard disable-while-typing, and the Active
                      Pen click rule (needs sudo in a terminal)
  --uninstall         Remove keybindings, menu entries, and the CLI link.
                      A symlink at the plugin path is removed. A checkout
                      that is already that path is left in place, so
                      omarchy plugin remove can delete it afterwards.
                      Does not delete the dubhagen.* overlay and power
                      clones, or ~/.local/bin/x1fold-battery-status.
  --no-shell-restart  Skip \`omarchy restart shell\`
  -h, --help          Show this help

Default install:
  use this repo as ~/.config/omarchy/plugins/${PLUGIN_ID}
  (symlink a separate checkout; leave an omarchy plugin add checkout in place)
  enable the bar widget, keybindings, on-screen keyboard, layer rules, menu
  refresh dubhagen.* clones of the stock overlays and power widget, then
  apply the clamshell inset and the dual-battery command. These ids are the
  publisher's, so the install does not take a clone in your own user namespace.
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
    'local x1fold = os.getenv("HOME") .. "/.config/omarchy/plugins/dubhagen.x1fold/bin/x1fold"',
    'o.launch_on_start("squeekboard")',
    'o.launch_on_start("env -u GDK_SCALE -u GDK_DPI_SCALE squeekboard")',
    'namespace = "dubhagen-x1fold-mask"',
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
                or "dubhagen-x1fold-mask" in lines[stop]
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
  local old repo_real live_real=""
  repo_real="$(readlink -f "$REPO")"
  for old in "${HOME}/.config/omarchy/plugins/"*; do
    [[ -L $old ]] || continue
    [[ $(basename "$old") == "$PLUGIN_ID" ]] && continue
    if [[ $(readlink -f "$old") == "$repo_real" ]]; then
      log "removing previous plugin link $old"
      rm -f "$old"
    fi
  done
  if [[ -e $LIVE || -L $LIVE ]]; then
    live_real="$(readlink -f "$LIVE")"
  fi
  # omarchy plugin add checks this repo out at LIVE. Running setup.sh from
  # that directory must leave the checkout where it is. Moving it aside and
  # symlinking LIVE at itself deletes the install out from under the script.
  if [[ -n $live_real && $live_real == "$repo_real" ]]; then
    log "plugin already installed at $LIVE"
  elif [[ -L $LIVE ]]; then
    log "replacing existing symlink $LIVE"
    ln -sfn "$REPO" "$LIVE"
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

clone_id_for() {
  # Publisher ids, never $USER.*. `omarchy plugin clone` always names the
  # copy after the unix user, which would take over that person's own slot.
  local source_id="$1"
  printf '%s.%s' "$PUBLISHER" "${source_id#omarchy.}"
}

refresh_owned_clone() {
  # Replace the publisher clone with a fresh copy of the current built-in.
  # These directories belong to this installer. The next setup.sh overwrites
  # any local edit inside them. Prints the installed path on stdout.
  local source_id="$1"
  local clone_id clone_dir source_dir source_manifest source_name stage info
  clone_id="$(clone_id_for "$source_id")"
  clone_dir="${PLUGINS_DIR}/${clone_id}"
  info=$(omarchy-plugin-catalog | jq -r --arg id "$source_id" '
    .[] | select(.firstParty and .id == $id)
    | [.sourceDir, .manifestPath, (.name // .id)] | @tsv
  ') || die "could not read the plugin catalog for ${source_id}"
  [[ -n $info ]] || die "unknown built-in plugin: ${source_id}"
  IFS=$'\t' read -r source_dir source_manifest source_name <<<"$info"
  [[ ${source_manifest##*/} == manifest.json ]] || die "${source_id} manifest is not manifest.json (${source_manifest})"
  [[ -d $source_dir ]] || die "missing source for ${source_id}: ${source_dir}"
  mkdir -p "$PLUGINS_DIR"
  # A leading dot keeps the staging dir out of the plugin scanner.
  stage=$(mktemp -d "${PLUGINS_DIR}/.x1fold-clone.XXXXXX")
  if ! cp -aL "$source_dir/." "$stage/"; then
    rm -rf "$stage"
    die "failed to copy ${source_id}"
  fi
  if ! jq \
    --arg id "$clone_id" \
    --arg name "$source_name" \
    --arg sourceId "$source_id" '
      .id = $id |
      .name = $name |
      if (.barWidget | type) == "object" then
        .barWidget.displayName = $name
      else
        .
      end |
      .omarchy = (
        (if (.omarchy | type) == "object" then .omarchy else {} end) +
        { clonedFrom: $sourceId }
      ) |
      del(.omarchy.clonePaths)
    ' "$stage/manifest.json" >"$stage/manifest.json.tmp"; then
    rm -rf "$stage"
    die "failed to rewrite the manifest for ${clone_id}"
  fi
  mv "$stage/manifest.json.tmp" "$stage/manifest.json"
  printf '%s\n' "$source_id" >"$stage/.x1fold-clone"
  rm -rf "$clone_dir"
  if ! mv "$stage" "$clone_dir"; then
    rm -rf "$stage"
    die "failed to install ${clone_dir}"
  fi
  printf '%s\n' "$clone_dir"
}

wait_for_plugin() {
  local clone_id="$1"
  local pass attempt discovered
  discovered=0
  for (( pass = 0; pass < 2; pass++ )); do
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    for (( attempt = 0; attempt < 40; attempt++ )); do
      if omarchy plugin list --json | jq -e --arg id "$clone_id" 'any(.[]; .id == $id)' >/dev/null; then
        discovered=1
        break
      fi
      sleep 0.05
    done
    (( discovered )) && break
  done
  (( discovered )) || die "cloned plugin ${clone_id} was not discovered"
}

plugin_is_enabled() {
  local id="$1"
  omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled)' >/dev/null
}

retire_foreign_owned_clone() {
  # Drop an older copy this installer made under some other id. A personal
  # clone of the same built-in has no ClamshellBounds, battery wrapper, or
  # .x1fold-clone marker, and is left alone. Disable before removing so the
  # shell puts the built-in back in the same bar slot.
  local source_id="$1" keep_id="$2"
  local dir manifest id
  for dir in "$PLUGINS_DIR"/*; do
    [[ -d $dir && ! -L $dir ]] || continue
    manifest="$dir/manifest.json"
    [[ -f $manifest ]] || continue
    id=$(jq -r --arg src "$source_id" '
      if .omarchy.clonedFrom == $src then .id else empty end
    ' "$manifest")
    [[ -n $id && $id != "$keep_id" ]] || continue
    [[ $(basename "$dir") == "$id" ]] || continue
    if [[ ! -f $dir/ClamshellBounds.qml && ! -f $dir/bin/battery-status && ! -f $dir/.x1fold-clone ]]; then
      continue
    fi
    if plugin_is_enabled "$id"; then
      log "disabling installer-owned clone ${id}"
      omarchy plugin disable "$id"
    fi
    log "removing installer-owned clone ${dir}"
    rm -rf "$dir"
  done
}

patch_power_command() {
  python3 - "$1" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = 'command: ["omarchy-battery-status", "--shell"]'
repl = 'command: ["x1fold-battery-status", "--shell"]'
if needle in text:
    if text.count(needle) != 1:
        sys.exit("expected exactly one stock battery command in " + str(path))
    path.write_text(text.replace(needle, repl, 1))
elif repl not in text:
    sys.exit("battery command not found in " + str(path))
PY
}

install_pack_status() {
  mkdir -p "$(dirname "$PACK_STATUS_BIN")"
  install -m 755 "$REPO/contrib/power/bin/battery-status" "$PACK_STATUS_BIN"
  log "pack battery status → ${PACK_STATUS_BIN}"
}

install_owned_clone() {
  local source_id="$1" kind="$2" entry="${3:-}"
  local clone_id clone_dir
  clone_id="$(clone_id_for "$source_id")"
  log "refreshing ${clone_id} from ${source_id}"
  clone_dir=$(refresh_owned_clone "$source_id")
  if [[ $kind == overlay ]]; then
    python3 "$REPO/contrib/clamshell/patch.py" apply "$clone_dir" "$entry"
    if [[ $entry == Menu.qml ]]; then
      log "clamshell inset and apps fallback on ${clone_id} (${entry})"
    else
      log "clamshell inset on ${clone_id} (${entry})"
    fi
  elif [[ $kind == power ]]; then
    patch_power_command "$clone_dir/Panel.qml"
    log "dual-battery command on ${clone_id}"
  else
    die "unknown clone kind ${kind}"
  fi
  wait_for_plugin "$clone_id"
  retire_foreign_owned_clone "$source_id" "$clone_id"
  if plugin_is_enabled "$clone_id"; then
    log "${clone_id} already enabled"
  else
    log "enabling ${clone_id}"
    omarchy plugin enable "$clone_id"
  fi
}

install_publisher_clones() {
  # Refresh every run, then patch only the delta. Enabling the new clone
  # happens after the previous installer-owned clone is disabled, so the
  # built-in returns to the same slot and the new id takes that slot.
  command -v jq >/dev/null || die "jq is required"
  command -v omarchy-plugin-catalog >/dev/null || die "omarchy-plugin-catalog is required"
  install_pack_status
  install_owned_clone omarchy.menu overlay Menu.qml
  install_owned_clone omarchy.image-picker overlay ImagePicker.qml
  install_owned_clone omarchy.osd overlay Osd.qml
  install_owned_clone omarchy.clipboard overlay Clipboard.qml
  install_owned_clone omarchy.emojis overlay Emojis.qml
  install_owned_clone omarchy.power power
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

# Hyprland 0.56 has no disable_while_typing timeout. This .so calls libinput.
# -fno-gnu-unique keeps the compositor's inline globals intact.
build_dwt_plugin() {
  local src="$REPO/contrib/dwt/dwt.cpp"
  local out="$REPO/contrib/dwt/x1fold-dwt.so"
  if ! command -v g++ >/dev/null || ! pkg-config --exists hyprland libinput; then
    warn "touchpad typing pause not built (need g++ and hyprland headers)"
    rm -f "$out"
    return 0
  fi
  # shellcheck disable=SC2046
  g++ -shared -fPIC -fno-gnu-unique -std=c++26 \
    $(pkg-config --cflags hyprland) \
    -o "$out" "$src" \
    $(pkg-config --libs libinput)
  log "touchpad typing pause → $out"
}

DWT_QUIRKS_DIR="${HOME}/.local/share/x1fold/libinput-quirks"
UWSM_ENV="${HOME}/.config/uwsm/env-hyprland"
UWSM_MARK_BEGIN="# dubhagen.x1fold: begin"
UWSM_MARK_END="# dubhagen.x1fold: end"

# libinput reads /etc/libinput/local-overrides.quirks and, if that file has an
# unknown key, drops every quirk. Setting LIBINPUT_QUIRKS_DIR skips that file.
# The directory is the system quirks plus this keyboard marked internal.
install_dwt_quirks() {
  [[ -d /usr/share/libinput ]] || {
    warn "no /usr/share/libinput; leaving the typing-pause quirks unset"
    return 0
  }
  mkdir -p "$DWT_QUIRKS_DIR"
  find "$DWT_QUIRKS_DIR" -maxdepth 1 -type l -delete
  local f
  for f in /usr/share/libinput/*.quirks; do
    [[ -e $f ]] || continue
    ln -s "$f" "$DWT_QUIRKS_DIR/$(basename "$f")"
  done
  install -m 644 "$REPO/contrib/libinput-x1fold.quirks" "$DWT_QUIRKS_DIR/90-x1fold-keyboard.quirks"
  mkdir -p "$(dirname "$UWSM_ENV")"
  local block
  block=$(cat <<EOF
$UWSM_MARK_BEGIN
# Skip /etc/libinput/local-overrides.quirks so one bad key cannot drop every quirk.
export LIBINPUT_QUIRKS_DIR="\$HOME/.local/share/x1fold/libinput-quirks"
$UWSM_MARK_END
EOF
)
  python3 - "$UWSM_ENV" "$UWSM_MARK_BEGIN" "$UWSM_MARK_END" "$block" <<'PY'
import pathlib, re, sys
path, begin, end, block = sys.argv[1:]
text = pathlib.Path(path).read_text() if pathlib.Path(path).exists() else ""
pattern = re.escape(begin) + r".*?" + re.escape(end) + r"\n?"
if begin in text and end in text:
    text = re.sub(pattern, block.rstrip() + "\n", text, count=1, flags=re.S)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text = text.rstrip() + ("\n\n" if text.strip() else "") + block.rstrip() + "\n"
pathlib.Path(path).write_text(text)
PY
  log "folio keyboard quirks → $DWT_QUIRKS_DIR (next Hyprland start)"
}

remove_dwt_quirks() {
  if [[ -f $UWSM_ENV ]]; then
    python3 - "$UWSM_ENV" "$UWSM_MARK_BEGIN" "$UWSM_MARK_END" <<'PY'
import pathlib, re, sys
path, begin, end = sys.argv[1:]
file = pathlib.Path(path)
if not file.exists():
    raise SystemExit
text = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "", file.read_text(), flags=re.S)
if text.strip():
    file.write_text(text)
else:
    file.unlink()
PY
  fi
  rm -rf "$DWT_QUIRKS_DIR"
}

strip_gtk_css_block() {
  local file="${HOME}/.config/gtk-3.0/gtk.css"
  [[ -f $file ]] || return 0
  python3 - "$file" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
updated = re.sub(
    r"\n?/\* [A-Za-z0-9.-]+\.x1fold squeekboard \*/.*?/\* [A-Za-z0-9.-]+\.x1fold squeekboard end \*/\n?",
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
  build_dwt_plugin
  install_dwt_quirks
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
  sudo install -m 644 "$REPO/contrib/udev-x1fold-pen.rules" /etc/udev/rules.d/66-x1fold-pen.rules
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
  remove_dwt_quirks
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
  elif [[ -d $LIVE && $(readlink -f "$LIVE") == $(readlink -f "$REPO") ]]; then
    log "left the plugin checkout at $LIVE"
    log "remove it with: omarchy plugin remove ${PLUGIN_ID}"
  fi
  if (( RESTART_SHELL )) && command -v omarchy >/dev/null; then
    omarchy restart shell
  fi
  log "left the dubhagen overlay and power clones, and ${PACK_STATUS_BIN}, in place"
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
install_publisher_clones

if (( BOOT )); then
  install_boot
fi

if (( RESTART_SHELL )); then
  log "restarting Omarchy shell"
  omarchy restart shell
fi

log "done. Left-click the fold icon on the bar, or run: x1fold status"
if (( ! BOOT )); then
  printf '\n    Bluetooth keyboard at LUKS, and Active Pen clicks:  ./setup.sh --boot\n\n'
fi
