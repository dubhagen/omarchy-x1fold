-- OLED keyboard-half mask: no fade, stay put.
hl.layer_rule({ match = { namespace = "mattd-x1fold-mask" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "^(squeekboard|osksqueekboard)$" }, no_anim = true })
hl.env("SQUEEKBOARD_FORCE", "1")
-- Screensaver is a covering-fullscreen terminal; drop chrome if it is not.
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
})
