-- ThinkPad Bluetooth TrackPoint Keyboard (X1FKeyboard, 17ef:613e).
-- Bluetooth HID is tagged external, so libinput will not suppress its
-- touchpad / TrackPoint while typing unless we force DWT on those pointers
-- and (via quirks) treat the keyboard as internal. Physical mouse buttons
-- sit under the spacebar. Disable-while-typing is what drops TrackPoint
-- and touchpad events during keystrokes; tap-to-click stays on.
hl.device({
  name = "x1fkeyboard-touchpad",
  disable_while_typing = true,
  tap_to_click = true,
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
