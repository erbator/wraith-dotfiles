-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/

-- Default beziers
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("overshoot",      { type = "bezier", points = { {0.5, 0.9}, {0.1, 1.1}     } })
hl.curve("myBezier",       { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05}   } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 700, dampening = 40 })
hl.curve("rubber",         { type = "spring", mass = 1, stiffness = 200,  dampening = 15 })

-- Animations
hl.animation({ leaf = "global",              enabled = true, speed = 0.7, bezier = "quick"                    })
hl.animation({ leaf = "windows",             enabled = true, speed = 5,   bezier = "myBezier", style = "popin 50%" })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 5,   bezier = "myBezier", style = "popin 50%" })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 0.4, bezier = "almostLinear"             })
hl.animation({ leaf = "layers",              enabled = true, speed = 5,   bezier = "myBezier", style = "fade"    })
hl.animation({ leaf = "layersIn",            enabled = true, speed = 5,   bezier = "myBezier", style = "fade"    })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 5,   bezier = "myBezier", style = "fade"    })
hl.animation({ leaf = "fade",                enabled = true, speed = 5,   bezier = "myBezier"                    })
hl.animation({ leaf = "fadeDim",             enabled = true, speed = 0.5, bezier = "quick"                    })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 5,   bezier = "myBezier", style = "slide"   })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 5,   bezier = "myBezier", style = "fade"})
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2,   bezier = "myBezier", style = "fade"})
