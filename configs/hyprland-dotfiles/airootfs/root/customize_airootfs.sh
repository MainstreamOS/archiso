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
systemctl unmask display-manager.service
systemctl enable sddm

# Enable user services
systemctl enable --global pipewire
systemctl enable --global pipewire-pulse
systemctl enable --global wireplumber
