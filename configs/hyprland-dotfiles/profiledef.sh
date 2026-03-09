#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="arch-hyprland"
iso_label="ARCH_HYPR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Arch Linux Hyprland"
iso_application="Arch Linux Hyprland Dotfiles Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr'
           'bios.syslinux.eltorito'
           'uefi-ia32.systemd-boot.esp'
           'uefi-x64.systemd-boot.esp'
           'uefi-x64.systemd-boot.eltorito')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/install-dotfiles"]="0:0:755"
  ["/usr/local/bin/dotfiles-first-login"]="0:0:755"
  ["/usr/local/bin/calamares-launch"]="0:0:755"
  ["/home/liveuser"]="1000:1000:750"
  ["/home/liveuser/.config"]="1000:1000:755"
  ["/home/liveuser/.config/hypr"]="1000:1000:755"
  ["/home/liveuser/.config/hypr/hyprland.conf"]="1000:1000:644"
  ["/home/liveuser/.config/kitty"]="1000:1000:755"
  ["/home/liveuser/.config/kitty/kitty.conf"]="1000:1000:644"
  ["/home/liveuser/Desktop"]="1000:1000:755"
  ["/home/liveuser/Desktop/install-arch.desktop"]="1000:1000:755"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
)
