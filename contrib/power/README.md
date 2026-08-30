# Dual-battery overlay for `omarchy.power`

The X1 Fold has two cells (BAT0 ~50 Wh and BAT1 ~14.6 Wh). Stock
`omarchy-battery-status` only prints the first. This overlay is **not** part of
`mattd.x1fold`; it is a cloned `omarchy.power` bar widget (`mattd.power`).

`setup.sh` runs `omarchy plugin clone omarchy.power` if needed, then copies:

- `Panel.qml` / `Model.js` — pack totals from UPower’s combined display device
- `bin/battery-status` — same `--shell` keys as Omarchy, using DisplayDevice + summed `power_now`

Uninstalling the fold plugin leaves `mattd.power` in place.
