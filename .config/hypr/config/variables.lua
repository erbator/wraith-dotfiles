-- Hyprland default apps
TERMINAL     = "kitty -1"
FILE_MANAGER = "dolphin"

-- UWSM app launcher prefix. Everything long-running we spawn (binds and
-- autostart) goes through it so it lands in its own systemd scope under
-- app-graphical.slice instead of living inside the compositor's cgroup.
-- Make this "" if you stop using UWSM.
LAUNCH_PREFIX = "uwsm app -- "

-- Monitors
MONITOR1 = "eDP-1"     -- integrated laptop display (primary)
MONITOR2 = "HDMI-A-1"  -- secondary external display
MONITOR3 = "DP-1"     -- third display; confirm name with `hyprctl monitors` once plugged in and update if different
PRIMARY_MONITOR = MONITOR1

-- Workspaces: which workspace IDs live on which monitor. workspaces.lua turns
-- this into the workspace rules and binds.lua derives its loop bounds from it,
-- so the two can't drift apart. The first ID of each monitor is its default.
WORKSPACE_LAYOUT = {
    { monitor = MONITOR1, workspaces = { 1, 2, 3, 4 } },
    { monitor = MONITOR2, workspaces = { 5, 6, 7, 8, 9, 10 } },
}

NUM_WORKSPACES = 0 -- total workspaces reachable via SUPER + number row (max 10)
NUM_WPM        = 0 -- most workspaces on a single monitor, used for the monitor-relative (m~N) binds
for _, entry in ipairs(WORKSPACE_LAYOUT) do
    NUM_WORKSPACES = NUM_WORKSPACES + #entry.workspaces
    NUM_WPM        = math.max(NUM_WPM, #entry.workspaces)
end
