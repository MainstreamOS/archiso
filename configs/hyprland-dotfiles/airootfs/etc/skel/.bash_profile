if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    exec start-hyprland
fi