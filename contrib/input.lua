-- ThinkPad Bluetooth TrackPoint Keyboard (X1FKeyboard, 17ef:613e).
-- Bluetooth HID is tagged external, so libinput will not suppress its
-- touchpad / TrackPoint while typing unless we force DWT on those pointers
-- and (via quirks) treat the keyboard as internal. Physical mouse buttons
-- sit under the spacebar; tap-to-click on the tiny keyboard touchpad is a
-- second source of stray clicks.
hl.device({
  name = "x1fkeyboard-touchpad",
  disable_while_typing = true,
  tap_to_click = false,
  natural_scroll = true,
  scroll_factor = 0.4,
})
hl.device({
  name = "x1fkeyboard-mouse",
  disable_while_typing = true,
})
hl.device({
  name = "x1fkeyboard-1",
  disable_while_typing = true,
})
hl.device({
  name = "x1fkeyboard",
  repeat_delay = 400,
  repeat_rate = 25,
})
