# Auto-start Hyprland on TTY1
if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export WLR_NO_HARDWARE_CURSORS=1
    # Force Vulkan renderer - required for RDNA 4 (RX 9070) and avoids GBM issues
    export WLR_RENDERER=vulkan
    export AMD_VULKAN_ICD=RADV
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 0700 "$XDG_RUNTIME_DIR"
    dbus-run-session Hyprland > /tmp/hyprland.log 2>&1
    echo "Hyprland exited with code $? — check /tmp/hyprland.log"
fi
