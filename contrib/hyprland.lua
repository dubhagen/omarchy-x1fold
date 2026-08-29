-- OLED keyboard-half mask: no fade, stay put.
hl.layer_rule({ match = { namespace = "mattd-x1fold-mask" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "^(squeekboard|osksqueekboard)$" }, no_anim = true })
hl.env("SQUEEKBOARD_FORCE", "1")
-- Clamshell: never map covering-fullscreen (that uses the whole OLED).
-- Size/move are refreshed from `x1fold apply` so TTE measures the half-size
-- pty on the first start instead of flashing full-panel then shrinking.
hl.window_rule({
  name = "mattd.x1fold-screensaver",
  match = { class = "org.omarchy.screensaver" },
  decorate = false,
  rounding = 0,
  no_shadow = true,
  border_size = 0,
  no_max_size = true,
  no_anim = true,
  float = true,
  fullscreen = false,
})
