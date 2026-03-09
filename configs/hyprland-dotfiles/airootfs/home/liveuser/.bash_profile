# Auto-start Hyprland on TTY1
if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export WLR_NO_HARDWARE_CURSORS=1
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 0700 "$XDG_RUNTIME_DIR"
    exec dbus-run-session Hyprland
fi
