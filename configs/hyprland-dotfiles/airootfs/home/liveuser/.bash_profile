# Auto-start Hyprland on TTY1
if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
    exec Hyprland
fi
