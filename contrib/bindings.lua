-- ThinkPad X1 Fold 16: orientation, clamshell, on-screen keyboard.
local x1fold = os.getenv("HOME") .. "/.config/omarchy/plugins/mattd.x1fold/bin/x1fold"
o.bind("SUPER + R", "Cycle fold orientation", x1fold .. " rotate cycle")
o.bind("SUPER + SHIFT + R", "Toggle clamshell", x1fold .. " clamshell toggle")
o.bind("SUPER + ALT + R", "On-screen keyboard", x1fold .. " osk toggle")
o.bind("SUPER + ALT + SHIFT + R", "Full fold panel", x1fold .. " tablet")
