#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="mainstreamos-desktop-linux"
iso_label="MAINSTREAM_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Mainstream"
iso_application="Mainstream Dotfiles Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="erofs"
airootfs_image_tool_options=('-zlzma,level=109' '-E' 'ztailpacking,fragments' '-C' '1048576')
# Every live boot entry, syslinux and systemd-boot alike, takes these through
# %KERNEL_PARAMS%, so the entries cannot drift apart and an edition adds its own
# in one place. The PXE entries keep theirs.
kernel_params_x86_64="copytoram=n cow_spacesize=1G"
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"

  # Install scripts
  ["/usr/local/bin/pre-install"]="0:0:755"
  ["/usr/local/bin/install-dotfiles"]="0:0:755"
  ["/usr/local/bin/install-gpu-drivers"]="0:0:755"
  ["/usr/local/bin/gpu-drivers"]="0:0:755"
  ["/usr/local/bin/install-limine"]="0:0:755"
  ["/usr/local/bin/post-install-boot"]="0:0:755"
  ["/usr/local/bin/mainstream-limine-windows"]="0:0:755"
  ["/usr/local/bin/post-install-login"]="0:0:755"
  ["/usr/local/bin/post-install-system"]="0:0:755"
  ["/usr/local/bin/post-install-theme"]="0:0:755"
  ["/usr/local/bin/post-install-snapshots"]="0:0:755"
  ["/usr/local/bin/post-install-hyprbars"]="0:0:755"
  ["/usr/local/bin/post-install-overview"]="0:0:755"
  ["/usr/local/bin/post-install-proton"]="0:0:755"
  ["/usr/local/lib/mainstream-postinstall-common.sh"]="0:0:644"
  ["/usr/local/lib/mac-config.sh"]="0:0:644"
  ["/usr/local/lib/mainstream-tr.sh"]="0:0:644"
  ["/usr/local/bin/mainstream-mac-firmware"]="0:0:755"
  ["/usr/local/bin/live-mac-quirks"]="0:0:755"
  ["/usr/local/bin/dotfiles-first-login"]="0:0:755"
  ["/usr/local/bin/calamares-autostart"]="0:0:755"
  ["/usr/local/bin/live-setup"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"

  # SDDM user Hyprland greeter config (sddm uid:gid = 963:963)
  ["/var/lib/sddm/.config/hypr"]="963:963:700"
  ["/var/lib/sddm/.config/hypr/hyprland.lua"]="963:963:600"

  ["/var/lib/hyprland-plugins"]="0:0:755"
  ["/var/lib/hyprland-plugins/hyprland-version"]="0:0:644"
  ["/usr/local/bin/cleanup-desktop-entries"]="0:0:755"
  ["/usr/local/bin/finalize-install"]="0:0:755"
  ["/usr/local/bin/post-install-verify"]="0:0:755"
  ["/usr/local/bin/save-install-log"]="0:0:755"
  ["/usr/local/bin/mainstream-install-health-notify"]="0:0:755"
  ["/usr/local/bin/power-key-helper"]="0:0:755"
  ["/usr/local/bin/disk-mounter"]="0:0:755"
  ["/usr/local/bin/gaming-tuning"]="0:0:755"
  ["/usr/local/bin/app-remover"]="0:0:755"
  ["/usr/local/bin/user-manager"]="0:0:755"
  ["/usr/local/bin/ollama-setup"]="0:0:755"
  ["/usr/local/bin/mainstream-update-helper"]="0:0:755"
  ["/usr/local/bin/mainstream-keyring-init"]="0:0:755"
  ["/usr/local/bin/mainstream-keyring-repair"]="0:0:755"
  ["/usr/local/bin/ai-cli-install"]="0:0:755"
  ["/usr/local/bin/mainstream-steam-seed-live"]="0:0:755"
  ["/usr/local/bin/updatems"]="0:0:755"
  ["/usr/local/bin/updatems-system"]="0:0:755"
  ["/usr/local/bin/pixie-sddm-keyboard-bridge.sh"]="0:0:755"
  ["/usr/share/polkit-1/actions/org.mainstreamos.disk-mounter.policy"]="0:0:644"
  ["/usr/share/polkit-1/actions/org.mainstreamos.gaming-tuning.policy"]="0:0:644"
  ["/usr/share/polkit-1/actions/org.mainstreamos.app-remover.policy"]="0:0:644"
  ["/usr/share/polkit-1/actions/org.mainstreamos.user-manager.policy"]="0:0:644"
  ["/usr/share/polkit-1/actions/org.mainstreamos.ollama-setup.policy"]="0:0:644"
  # Calamares autostart (XDG autostart — read by dex/autostart managers)
  ["/etc/xdg/autostart/calamares.desktop"]="0:0:644"

  # Bootloader config template
  ["/etc/limine.conf.template"]="0:0:644"

  ["/etc/firewalld/zones/MainstreamWorkstation.xml"]="0:0:644"

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
  ["/etc/skel/.config/hypr/hyprland/shellOverrides"]="0:0:755"
  ["/etc/skel/.config/hypr/hyprland/shellOverrides/main.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/hyprland.lua"]="0:0:644"
  ["/etc/skel/.config/hypr/monitors.lua"]="0:0:644"
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


  # System config
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/etc/sudoers.d/liveuser"]="0:0:440"
  ["/etc/sudoers.d/zz-gpu-drivers"]="0:0:440"
  ["/etc/systemd/system/systemd-firstboot.service"]="0:0:644"
)

# mkarchiso copies airootfs without its modes, and skel is what every account
# made after install starts from, so each script in it is named here from what
# the tree holds when the image is built. A list kept by hand fell behind
# whenever the dotfiles gained a script.
while IFS= read -r -d '' _skel_exec; do
    file_permissions["/${_skel_exec#airootfs/}"]="0:0:755"
done < <(cd -- "${profile:-.}" && find airootfs/etc/skel -type f -perm -u+x -print0 2>/dev/null)
unset _skel_exec
