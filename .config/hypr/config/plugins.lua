-- Plugin configuration

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    -- Custom preset, exact clone of the built-in "glass" preset
    -- (values taken from BuiltInPresets.hpp's makeGlass()).
    hg.preset("aurora", {
        blur_strength        = 1.0,
        blur_iterations      = 2,
        lens_distortion       = 0.3,
        refraction_strength  = 4.1,
        chromatic_aberration = 0.1,
        fresnel_strength     = 0.2,
        specular_strength    = 0.8,
        glass_opacity        = 1.0,
        edge_thickness        = 0.06,
        tint_color            = 0xffffff00,
        vibrancy = 0.5,
        saturation = 1.1,
        contrast = 1.2,
        brightness = 1,

        dark = {
            adaptive_dim = 0.3,
        },
        light = {
            adaptive_boost = 0.3,
        },
    })
end

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

