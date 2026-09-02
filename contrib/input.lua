-- ThinkPad TrackPoint Keyboard: Bluetooth (17ef:613e, X1FKeyboard) and
-- USB-C (17ef:6142, Primax "... Keyboard - USB"). Both buses tag the
-- touchpad as external, so disable-while-typing never pairs unless we
-- force DWT on the pointers and (via quirks) mark keyboard/touchpad
-- internal. Physical mouse buttons sit under the spacebar.

local function x1fold_touchpad(name)
  hl.device({
    name = name,
    disable_while_typing = true,
    tap_to_click = true,
    natural_scroll = true,
    scroll_factor = 0.4,
  })
end

local function x1fold_pointer(name)
  hl.device({
    name = name,
    disable_while_typing = true,
  })
end

local function x1fold_keyboard(name)
  -- Bluetooth HID can emit extra repeats on flaky links. Keep the same
  -- typing feel on USB-C so swapping the cable does not change repeat.
  hl.device({
    name = name,
    repeat_delay = 400,
    repeat_rate = 25,
  })
end

x1fold_touchpad("x1fkeyboard-touchpad")
x1fold_pointer("x1fkeyboard-mouse")
x1fold_pointer("x1fkeyboard-1")
x1fold_keyboard("x1fkeyboard")

x1fold_touchpad("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb-touchpad")
x1fold_pointer("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb-1")
x1fold_pointer("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb-2")
x1fold_pointer("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb-system-control-1")
x1fold_pointer("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb-consumer-control-1")
x1fold_keyboard("primax-electronics-ltd.-thinkpad-bluetooth-trackpoint-keyboard---usb")

-- OSK is a virtual keyboard with its own XKB maps. Do not share Caps/Shift
-- with the hardware keyboard (Omarchy's shift:both_capslock_cancel then
-- looks like Caps Lock after one capital), and do not let OSK Backspace
-- fire Super+Backspace.
hl.config({
  input = {
    virtualkeyboard = {
      share_states = 0,
      release_pressed_on_close = true,
    },
  },
})
hl.device({
  name = "hl-virtual-keyboard-wvkbd-deskintl",
  keybinds = false,
  share_states = 0,
  kb_options = "",
  release_pressed_on_close = true,
})
