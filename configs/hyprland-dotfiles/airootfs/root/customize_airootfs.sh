#!/usr/bin/env bash

set -e

# Set blank password so autologin works
passwd -d liveuser

# Allow liveuser to use sudo without password
echo "liveuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/liveuser

# Fix hyprland.desktop to use start-hyprland wrapper
sed -i 's/Exec=Hyprland/Exec=start-hyprland/' /usr/share/wayland-sessions/hyprland.desktop

# Enable essential services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl disable sddm

# TTY1 autologin for faster boot on live session
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -a liveuser --noclear %I \$TERM
EOF

# Enable user services
systemctl enable --global pipewire
systemctl enable --global pipewire-pulse
systemctl enable --global wireplumber

# Override default shellprocess.conf to prevent fallback to test commands
cat > /usr/share/calamares/modules/shellprocess.conf << 'EOF'
---
# Default shellprocess - intentionally empty
# Named instances (shellprocess@name) handle all actual commands
script:
    - command: "/usr/bin/true"
      timeout: 10
EOF
