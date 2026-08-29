-- OLED keyboard-half mask: no fade, stay put.
hl.layer_rule({ match = { namespace = "mattd-x1fold-mask" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "^(squeekboard|osksqueekboard)$" }, no_anim = true })
hl.env("SQUEEKBOARD_FORCE", "1")
