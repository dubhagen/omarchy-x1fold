-- Squeekboard stays resident so Super+Alt+R can show it instantly.
-- Drop Omarchy's GDK_SCALE=2 so GTK uses fractional 1.6 like the OLED.
o.launch_on_start("env -u GDK_SCALE -u GDK_DPI_SCALE squeekboard")
