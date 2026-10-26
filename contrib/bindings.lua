-- ThinkPad X1 Fold 16: orientation, clamshell, on-screen keyboard.
local x1fold = os.getenv("HOME") .. "/.config/omarchy/plugins/mattd.x1fold/bin/x1fold"
o.bind("SUPER + R", "Cycle fold orientation", x1fold .. " rotate cycle")
o.bind("SUPER + SHIFT + R", "Toggle clamshell", x1fold .. " clamshell toggle")
o.bind("SUPER + ALT + R", "On-screen keyboard", x1fold .. " osk toggle")
o.bind("SUPER + ALT + SHIFT + R", "Full fold panel", x1fold .. " tablet")

-- wvkbd's Sup key latches until the next key. Keep these chords on every
-- keyboard except the on-screen one, so a still-latched Sup followed by
-- Backspace deletes instead of toggling transparency, gaps, or aspect.
local osk_device = "hl-virtual-keyboard-wvkbd-deskintl"
local function x1fold_hardware_only(keys, description, command)
  hl.unbind(keys)
  o.bind(keys, description, command, {
    device = { inclusive = false, list = { osk_device } },
  })
end

x1fold_hardware_only("SUPER + BACKSPACE", "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")
x1fold_hardware_only("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")
x1fold_hardware_only("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", "omarchy-hyprland-window-single-square-aspect-toggle")
