-- OLED keyboard-half mask: no fade, stay put.
hl.layer_rule({ match = { namespace = "mattd-x1fold-mask" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "mattd-x1fold-wallpaper" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "mattd-x1fold-ss-dismiss" }, no_anim = true, animation = "none", order = 50 })
-- The strip is a Top layer (above fullscreen, below Overlay). wvkbd is
-- Overlay, so the keys stay above it. order 10 keeps the strip behind any
-- other Top surface that uses the default order.
hl.layer_rule({ match = { namespace = "^mattd-x1fold-osk-mask$" }, no_anim = true, animation = "none", order = 10 })
hl.layer_rule({ match = { namespace = "^wvkbd$" }, no_anim = true, order = 0 })

-- Default is Omarchy's covering-fullscreen + slide. Clamshell apply()
-- evals this named rule to a half-panel float; leaving tablet as
-- fullscreen=false made the saver a tiny floating window.
hl.window_rule({
  name = "mattd.x1fold-screensaver",
  match = { class = "org.omarchy.screensaver" },
  decorate = false,
  rounding = 0,
  no_shadow = true,
  border_size = 0,
  no_max_size = true,
  float = true,
  fullscreen = true,
  animation = "slide",
})
hl.window_rule({
  name = "mattd.x1fold-edge-fs",
  match = { tag = "x1fold-clamshell-fs" },
  decorate = false,
  rounding = 0,
  no_shadow = true,
  border_size = 0,
  no_anim = true,
})

local x1fold = os.getenv("HOME") .. "/.config/omarchy/plugins/mattd.x1fold/bin/x1fold"
local x1fold_placing_lock = (os.getenv("HOME") or "") .. "/.local/state/omarchy/x1fold/fs-placing.lock"

local function x1fold_placing()
  local file = io.open(x1fold_placing_lock, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function x1fold_flag(name)
  local path = (os.getenv("HOME") or "") .. "/.local/state/omarchy/x1fold/state.json"
  local file = io.open(path, "r")
  if not file then
    return false
  end
  local body = file:read("*a") or ""
  file:close()
  return string.find(body, '"' .. name .. '"%s*:%s*true') ~= nil
end

local function x1fold_clamshell(_mon)
  -- Do not use reserved.bottom: the OSK exclusive zone is also a bottom
  -- reserve, and treating it as clamshell floats the screensaver.
  return x1fold_flag("clamshell")
end

local function x1fold_viewport(_mon)
  -- Folio clamshell, or the on-screen keyboard: fullscreen stays above that
  -- bottom band. The keyboard itself is not the screensaver.
  return x1fold_flag("clamshell") or x1fold_flag("osk")
end

local function x1fold_has_tag(w, name)
  local tags = w and w.tags
  if type(tags) ~= "table" then
    return false
  end
  for _, tag in pairs(tags) do
    if tag == name or tag == name .. "*" then
      return true
    end
  end
  return false
end

-- First key/click while the clamshell screensaver is up unparks the bar
-- and then closes the saver. Catchall is only legal inside a submap.
-- "reset" after the bind fires so we are not stuck in the submap.
hl.define_submap("x1fold-ss", "reset", function()
  hl.bind("catchall", hl.dsp.exec_cmd(x1fold .. " dismiss-screensaver"), {
    description = "X1 Fold: unpark bar then close screensaver",
    dont_inhibit = true,
  })
  hl.bind("mouse:272", hl.dsp.exec_cmd(x1fold .. " dismiss-screensaver"), {
    description = "X1 Fold: dismiss screensaver",
    mouse = true,
    click = true,
  })
  hl.bind("mouse:273", hl.dsp.exec_cmd(x1fold .. " dismiss-screensaver"), {
    description = "X1 Fold: dismiss screensaver",
    mouse = true,
    click = true,
  })
end)

local function x1fold_ss_submap(on)
  if on then
    hl.dispatch(hl.dsp.submap("x1fold-ss"))
  else
    hl.dispatch(hl.dsp.submap("reset"))
  end
end

hl.on("window.open", function(w)
  if w == nil or w.class ~= "org.omarchy.screensaver" then
    return
  end
  -- Park the OSK overlay so it cannot paint above the saver. SIGUSR1,
  -- not a process kill (that releases keys and dismisses the saver).
  hl.dispatch(hl.dsp.exec_cmd(x1fold .. " osk park"))
  if not x1fold_clamshell(w.monitor) then
    x1fold_ss_submap(false)
    return
  end
  x1fold_ss_submap(true)
  hl.dispatch(hl.dsp.exec_cmd(x1fold .. " constrain-screensaver " .. tostring(w.address)))
end)

hl.on("window.close", function(w)
  if w == nil or w.class ~= "org.omarchy.screensaver" then
    return
  end
  x1fold_ss_submap(false)
end)

-- Client-initiated covering (YouTube) is remapped onto the visible half.
-- Super+F in clamshell never goes covering; it toggles the half-panel float.
hl.on("window.fullscreen", function(w)
  if w == nil or x1fold_placing() then
    return
  end
  if w.class == "org.omarchy.screensaver" then
    if x1fold_clamshell(w.monitor) then
      hl.dispatch(hl.dsp.exec_cmd(x1fold .. " constrain-screensaver " .. tostring(w.address)))
    end
    return
  end
  if not x1fold_viewport(w.monitor) then
    return
  end
  local client_fs = tonumber(w.fullscreen_client) or 0
  -- Super+F does not go covering in clamshell. YouTube still requests covering
  -- (internal=2); remap it. Ignore covering while already remapped so a
  -- re-request cannot look like an exit. internal=0 client=0 while tagged is
  -- a real client un-fullscreen (Escape).
  if w.fullscreen == 2 then
    if x1fold_has_tag(w, "x1fold-clamshell-fs") then
      return
    end
    hl.dispatch(hl.dsp.exec_cmd(x1fold .. " constrain-fullscreen " .. tostring(w.address)))
    return
  end
  if w.fullscreen == 0 and client_fs == 0 and x1fold_has_tag(w, "x1fold-clamshell-fs") then
    hl.dispatch(hl.dsp.exec_cmd(x1fold .. " fullscreen off " .. tostring(w.address)))
  end
end)

-- Clamshell Super+F floats the visible half directly (no covering flash).
hl.unbind("SUPER + F")
o.bind("SUPER + F", "Full screen", function()
  local w = hl.get_active_window()
  if w ~= nil and x1fold_viewport(w.monitor) then
    hl.dispatch(hl.dsp.exec_cmd(x1fold .. " fullscreen toggle " .. tostring(w.address)))
    return
  end
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
end)
