#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="mainstreamos-desktop-linux"
iso_label="MAINSTREAM_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Mainstream"
iso_application="Mainstream Dotfiles Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.limine'
           'uefi.limine')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '3' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"

  # Install scripts
  ["/usr/local/bin/pre-install"]="0:0:755"
  ["/usr/local/bin/install-yay"]="0:0:755"
  ["/usr/local/bin/install-dotfiles"]="0:0:755"
  ["/usr/local/bin/install-gpu-drivers"]="0:0:755"
  ["/usr/local/bin/install-limine"]="0:0:755"
  ["/usr/local/bin/post-install"]="0:0:755"
  ["/usr/local/bin/dotfiles-first-login"]="0:0:755"
  ["/usr/local/bin/calamares-autostart"]="0:0:755"
  ["/usr/local/bin/live-setup"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"

  # SDDM user Hyprland greeter config (sddm uid:gid = 963:963)
  ["/var/lib/sddm/.config/hypr"]="963:963:700"
  ["/var/lib/sddm/.config/hypr/hyprland.conf"]="963:963:600"
  ["/usr/local/bin/cleanup-desktop-entries"]="0:0:755"
  ["/usr/local/bin/power-key-helper"]="0:0:755"
  # Calamares autostart (XDG autostart — read by dex/autostart managers)
  ["/etc/xdg/autostart/calamares.desktop"]="0:0:644"

  # Bootloader config template
  ["/etc/limine.conf.template"]="0:0:644"

  # Skel files — copied to liveuser home on boot
  ["/etc/skel/.bash_profile"]="0:0:644"
  ["/etc/skel/.config"]="0:0:755"
  ["/etc/skel/.config/hypr"]="0:0:755"
  ["/etc/skel/.config/hypr/custom"]="0:0:755"
  ["/etc/skel/.config/hypr/custom/env.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/execs.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/general.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/keybinds.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/rules.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/variables.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/custom/scripts"]="0:0:755"
  ["/etc/skel/.config/hypr/custom/scripts/bluetooth-autoconnect.sh"]="0:0:755"
  ["/etc/skel/.config/hypr/custom/scripts/__restore_video_wallpaper.sh"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/colors.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/env.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/execs.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/general.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/keybinds.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/rules.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/variables.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland/scripts"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/scripts/launch_first_available.sh"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/scripts/workspace_action.sh"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/shellOverrides"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/shellOverrides/main.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/workspaces.lua"]="0:0:644"
  ["/etc/skel/.config/quickshell"]="0:0:755"
  ["/etc/skel/.config/quickshell/ii"]="0:0:755"
  ["/etc/skel/.config/qt6ct"]="0:0:755"
  ["/etc/skel/.config/qt6ct/qt6ct.conf"]="0:0:644"
  ["/etc/skel/.config/kitty"]="0:0:755"
  ["/etc/skel/.config/kitty/kitty.conf"]="0:0:644"

  # Liveuser desktop shortcut
  ["/home/liveuser/Desktop"]="1000:1000:755"
  ["/home/liveuser/Desktop/install-arch.desktop"]="1000:1000:755"

  # Sleep hook
  ["/usr/lib/systemd/system-sleep/hyprland-dpms.sh"]="0:0:755"

  # Plugin rebuild hooks (pacman PostTransaction calls these on hyprland install/upgrade)
  ["/usr/local/lib/hyprbars/rebuild.sh"]="0:0:755"
  ["/usr/local/lib/scrolloverview/rebuild.sh"]="0:0:755"

  # System config
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/etc/sudoers.d/liveuser"]="0:0:440"
  ["/etc/systemd/system/systemd-firstboot.service"]="0:0:644"
)
