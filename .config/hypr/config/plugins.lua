-- Plugin configuration
-- Everything hyprglass-related is guarded: the plugin is loaded by
-- `hyprpm reload` at startup, and after a Hyprland update it stays unloaded
-- until you run `hyprpm update`. Setting plugin:hyprglass:* while it is not
-- loaded is a config error, so only touch it when it is actually there
-- (plugin load triggers a config reload, which re-runs this file).

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    -- Custom preset, exact clone of the built-in "glass" preset
    -- (values taken from BuiltInPresets.hpp's makeGlass()).
    hg.preset("aurora", {
        blur_strength        = 1.0,
        blur_iterations      = 1,
        lens_distortion       = 1.0,
        refraction_strength  = 5,
        chromatic_aberration = 0.03,
        fresnel_strength     = 0.1,
        specular_strength    = 0.1,
        glass_opacity        = 1.2,
        edge_thickness        = 0.01,

        vibrancy = 0.5,
        saturation = 1.1,
        contrast = 1.2,
        brightness = 1,

        dark = {
            adaptive_dim = 0.3,
        },
        light = {
            adaptive_boost = 0.2,
        },
    })

    hl.config({
        plugin = {
            hyprglass = {
                enabled = 1,
                manage_window_blur = 1,
                default_theme = "dark",
                default_preset = "aurora",
            },
        },
    })
end
