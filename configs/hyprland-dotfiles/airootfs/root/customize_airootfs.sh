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

# Let Plymouth animate while SDDM/Hyprland starts so the DRM handoff is
# seamless. Move plymouth-quit out of multi-user.target (which would block
# SDDM from starting) into graphical.target so it fires after the display
# manager is already up.
rm -f /etc/systemd/system/multi-user.target.wants/plymouth-quit.service
rm -f /etc/systemd/system/multi-user.target.wants/plymouth-quit-wait.service
mkdir -p /etc/systemd/system/graphical.target.wants/
ln -sf /usr/lib/systemd/system/plymouth-quit.service \
    /etc/systemd/system/graphical.target.wants/plymouth-quit.service

# Enable user services
systemctl enable --global pipewire
systemctl enable --global pipewire-pulse
systemctl enable --global wireplumber
