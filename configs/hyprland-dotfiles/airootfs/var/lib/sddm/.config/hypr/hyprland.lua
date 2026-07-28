-- Hyprland config for the SDDM greeter's own compositor instance.
-- Separate from the user session's config, which lives in ~/.config/hypr.
--
-- Lua rather than .conf: Hyprland 0.56.1 shows a deprecation notice on any
-- .conf config, and the greeter is the first thing anyone sees. Support for
-- the format goes away entirely in 0.57.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        disable_watchdog_warning = true,
    },
    animations = {
        enabled = false,
    },
})

hl.window_rule({ match = { class = "^(sddm-greeter-qt6)$" }, fullscreen = true })
