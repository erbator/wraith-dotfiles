-- Auto-start config
-- This is a UWSM session: Hyprland itself exports WAYLAND_DISPLAY & co. to the
-- systemd activation environment and UWSM preloads ~/.config/uwsm/env, so no
-- dbus-update-activation-environment call is needed here. Long-running programs
-- go through LAUNCH_PREFIX (uwsm app) so each gets its own systemd scope.
-- Anything that ships a systemd user unit is better enabled with
-- `systemctl --user enable --now <unit>` than listed here.

hl.on("hyprland.start", function ()
    hl.exec_cmd(LAUNCH_PREFIX .. "awww-daemon")
    hl.exec_cmd(LAUNCH_PREFIX .. "wl-paste --type text --watch cliphist store")
    hl.exec_cmd(LAUNCH_PREFIX .. "wl-paste --type image --watch cliphist store")
    hl.exec_cmd(LAUNCH_PREFIX .. "quickshell -c dynamic-glacier")
end)
