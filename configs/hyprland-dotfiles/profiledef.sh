#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="arch-hyprland"
iso_label="ARCH_HYPR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Mainstream"
iso_application="Mainstream Dotfiles Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
arch="x86_64"
buildmodes=('iso')
bootmodes=('bios.limine'
           'uefi.limine')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"

  # Install scripts
  ["/usr/local/bin/pre-install"]="0:0:755"
  ["/usr/local/bin/install-yay"]="0:0:755"
  ["/usr/local/bin/install-dotfiles"]="0:0:755"
  ["/usr/local/bin/install-limine"]="0:0:755"
  ["/usr/local/bin/post-install"]="0:0:755"
  ["/usr/local/bin/dotfiles-first-login"]="0:0:755"
  ["/usr/local/bin/calamares-launch"]="0:0:755"
  ["/usr/local/bin/calamares-autostart"]="0:0:755"
  ["/usr/local/bin/live-setup"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/sddm-bg-helper"]="0:0:755"
  ["/etc/skel/.config/hypr/scripts/init-qs.sh"]="0:0:755"

  # Calamares autostart (XDG autostart — read by dex/autostart managers)
  ["/etc/xdg/autostart/calamares.desktop"]="0:0:644"

  # Bootloader config template
  ["/etc/limine.conf.template"]="0:0:644"

  # Skel files — copied to liveuser home on boot
  ["/etc/skel/.bash_profile"]="0:0:644"
  ["/etc/skel/.config"]="0:0:755"
  ["/etc/skel/.config/hypr"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland.conf"]="0:0:644"
  ["/etc/skel/.config/kitty"]="0:0:755"
  ["/etc/skel/.config/kitty/kitty.conf"]="0:0:644"

  # Liveuser desktop shortcut
  ["/home/liveuser/Desktop"]="1000:1000:755"
  ["/home/liveuser/Desktop/install-arch.desktop"]="1000:1000:755"

  # System config
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/etc/systemd/system/systemd-firstboot.service"]="0:0:644"
)
