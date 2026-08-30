function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function laptopBatteries(devices) {
  var out = []
  var vals = devices && devices.values ? devices.values : []
  for (var i = 0; i < vals.length; i++) {
    var d = vals[i]
    if (d && d.isLaptopBattery && d.isPresent)
      out.push(d)
  }
  return out
}

function packTotals(batteries) {
  var energy = 0
  var capacity = 0
  var rate = 0
  for (var i = 0; i < batteries.length; i++) {
    var d = batteries[i]
    energy += Number(d.energy || 0)
    capacity += Number(d.energyCapacity || 0)
    rate += Number(d.changeRate || 0)
  }
  return { energy: energy, capacity: capacity, rate: rate }
}

function packFraction(batteries, displayDevice) {
  var pack = packTotals(batteries)
  if (batteries.length >= 2 && pack.capacity > 0)
    return Math.max(0, Math.min(1, pack.energy / pack.capacity))
  var path = displayDevice ? String(displayDevice.nativePath || "") : ""
  if (displayDevice && displayDevice.isPresent && path.indexOf("BAT") !== 0 && Number(displayDevice.energyCapacity || 0) > 0)
    return Math.max(0, Math.min(1, Number(displayDevice.percentage || 0)))
  if (pack.capacity > 0)
    return Math.max(0, Math.min(1, pack.energy / pack.capacity))
  return batteryFraction(displayDevice)
}

function formatWatts(rate) {
  var rounded = Number(rate || 0).toFixed(1)
  if (rounded.slice(-2) === ".0")
    rounded = rounded.slice(0, -2)
  return rounded + "W"
}

function formatWattHours(capacity) {
  return Math.round(Number(capacity || 0)) + "Wh"
}

function formatDurationHours(hours) {
  var value = Number(hours || 0)
  if (!(value > 0) || value > 72)
    return ""
  var h = Math.floor(value)
  var m = Math.round((value - h) * 60)
  if (m === 60) {
    h += 1
    m = 0
  }
  if (h > 0 && m > 0)
    return h + "h " + m + "m"
  if (h > 0)
    return h + "h"
  return m + "m"
}

function packTime(batteries, discharging) {
  var pack = packTotals(batteries)
  if (pack.rate <= 0.05)
    return ""
  var hours = discharging ? (pack.energy / pack.rate) : ((pack.capacity - pack.energy) / pack.rate)
  return formatDurationHours(hours)
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    laptopBatteries: laptopBatteries,
    packTotals: packTotals,
    packFraction: packFraction,
    formatWatts: formatWatts,
    formatWattHours: formatWattHours,
    formatDurationHours: formatDurationHours,
    packTime: packTime,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
