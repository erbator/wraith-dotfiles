-- Input configuration

hl.config({
    input = {
        -- sensitivity = -0.25,
        accel_profile = "flat",
        kb_layout = "hu",
        touchpad = {
            -- Otherwise the touchpad freezes while holding WASD in games
            disable_while_typing = false,
        },
    },
    -- Uncomment the section below to enable software cursors; this can help with cursor display or behavior issues
    -- cursor = {
    --     no_hardware_cursors = 1,
    -- },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "close" })
hl.gesture({ fingers = 3, direction = "up",         action = "fullscreen" })
-- Live cursor zoom (same as SUPER + Minus / ó). 3 fingers so apps keep their own 2-finger pinch.
hl.gesture({ fingers = 3, direction = "pinch",      action = "cursor_zoom", zoom_level = 1, mode = "live" })
