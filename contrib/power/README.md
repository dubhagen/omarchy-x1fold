# Dual-battery command for `omarchy.power`

The X1 Fold has two cells (BAT0 ~50 Wh and BAT1 ~14.6 Wh). The power panel’s
icon already follows UPower’s combined DisplayDevice. Its size, rate, and
time come from `omarchy-battery-status`, which stops at the first cell.

This is not part of `dubhagen.x1fold`. `setup.sh` keeps a publisher-owned
clone, `dubhagen.power`, so a new install does not take a slot in the user’s
own plugin namespace. Every run copies the current `omarchy.power` and
changes one line in `Panel.qml`:

```qml
command: ["x1fold-battery-status", "--shell"]
```

`bin/battery-status` is installed to `~/.local/bin/x1fold-battery-status`.
With one cell, or without a present DisplayDevice, it execs the stock tool.
With two or more power-supply batteries, `--shell` keeps the stock cycles,
threshold, and holding state, and replaces percentage, size, rate, and time
with the pack. Human-readable output stays the stock tool.

`omarchy plugin clone` is not used. It always names the copy `$USER.power`.

The next `./setup.sh` overwrites `~/.config/omarchy/plugins/dubhagen.power`.
Uninstalling the fold plugin leaves that clone and `x1fold-battery-status`
in place, because the panel still calls the command.
