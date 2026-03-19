# =============================================================================
# Limine bootmode support for archiso
# =============================================================================
# This file is appended to the mkarchiso script by build.sh so that the
# dynamic function dispatch in mkarchiso can call the functions below.
#
# Two boot modes are provided:
#   bios.limine   — El Torito BIOS boot via limine-bios-cd.bin
#   uefi.limine   — UEFI boot via a FAT ESP image containing BOOTX64.EFI
#
# After mkarchiso creates the ISO, build.sh runs:
#   limine bios-install <iso>
# to embed Limine's MBR bootstrap for hybrid USB+CD BIOS boot support.
#
# Requirements on the BUILD HOST:
#   pacman -S limine dosfstools mtools
#
# Variables available from mkarchiso (used below):
#   ${arch}         — e.g. x86_64
#   ${iso_label}    — ISO volume label
#   ${iso_uuid}     — ISO UUID (build timestamp)
#   ${install_dir}  — e.g. arch
#   ${isofs_dir}    — ISO 9660 staging directory
#   ${work_dir}     — mkarchiso working directory
#   ${efibootimg}   — path to the FAT EFI image (set before _make_bootmodes runs)
#   ${efiboot_files[]} — array used by _make_efibootimg to size the FAT image
#   ${bootmodes[@]} — the full list of enabled boot modes
#   ${bootmode}     — current boot mode being validated/built

# =============================================================================
# Shared helper
# =============================================================================

# Write limine.conf to the ISO root with placeholder substitution.
# Guards against double-write if both bios.limine and uefi.limine are active.
_make_limine_iso_config() {
    [[ -f "${isofs_dir}/limine.conf" ]] && return
    _msg_info "Writing Limine configuration to ISO root..."
    sed \
        -e "s|%ARCHISO_LABEL%|${iso_label}|g" \
        -e "s|%ARCHISO_UUID%|${iso_uuid}|g" \
        -e "s|%INSTALL_DIR%|${install_dir}|g" \
        -e "s|%ARCH%|${arch}|g" \
        "${profile}/limine-iso.conf" > "${isofs_dir}/limine.conf"
}

# =============================================================================
# bios.limine
# =============================================================================

_validate_requirements_bootmode_bios.limine() {
    if [[ "${arch}" != 'x86_64' && "${arch}" != 'i686' ]]; then
        _msg_error "Validating '${bootmode}': BIOS boot is not supported on '${arch}'." 0
        (( validation_error=validation_error+1 ))
        return
    fi
    local _f
    for _f in /usr/share/limine/limine-bios-cd.bin /usr/share/limine/limine-bios.sys; do
        if [[ ! -f "${_f}" ]]; then
            _msg_error "Validating '${bootmode}': ${_f} not found. Install 'limine' on the build host." 0
            (( validation_error=validation_error+1 ))
        fi
    done
    if [[ ! -f "${profile}/limine-iso.conf" ]]; then
        _msg_error "Validating '${bootmode}': ${profile}/limine-iso.conf not found." 0
        (( validation_error=validation_error+1 ))
    fi
}

_make_bootmode_bios.limine() {
    _msg_info "Setting up Limine for BIOS booting..."
    # Limine BIOS CD boot binary (El Torito boot image)
    install -m 0644 -- /usr/share/limine/limine-bios-cd.bin "${isofs_dir}/limine-bios-cd.bin"
    # Limine BIOS system binary (needed by limine bios-install for USB hybrid)
    install -m 0644 -- /usr/share/limine/limine-bios.sys "${isofs_dir}/limine-bios.sys"
    _make_limine_iso_config
    _msg_info "Done! Limine set up for BIOS booting."
}

_add_xorrisofs_options_bios.limine() {
    xorrisofs_options+=(
        # El Torito BIOS boot entry pointing to Limine's BIOS CD binary
        '-b'              'limine-bios-cd.bin'
        # El Torito boot catalog (also used by the UEFI entry added by uefi.limine)
        '-eltorito-catalog' 'boot.cat'
        # Required for El Torito boot with Limine
        '-no-emul-boot'
        '-boot-load-size' '4'
        '-boot-info-table'
        # Limine requires the extended boot info table for BIOS boot
        '--grub2-boot-info'
        # Offset the first partition so GPT headers fit; shared with uefi.limine
        '-partition_offset' '16'
    )
}

# =============================================================================
# uefi.limine
# =============================================================================

_validate_requirements_bootmode_uefi.limine() {
    # Re-use the common UEFI checks (mkfs.fat, mmd/mcopy availability, arch)
    _validate_common_requirements_bootmode_uefi
    local _f
    for _f in /usr/share/limine/BOOTX64.EFI; do
        if [[ ! -f "${_f}" ]]; then
            _msg_error "Validating '${bootmode}': ${_f} not found. Install 'limine' on the build host." 0
            (( validation_error=validation_error+1 ))
        fi
    done
    if [[ ! -f "${profile}/limine-iso.conf" ]]; then
        _msg_error "Validating '${bootmode}': ${profile}/limine-iso.conf not found." 0
        (( validation_error=validation_error+1 ))
    fi
}

_make_bootmode_uefi.limine() {
    _msg_info "Setting up Limine for UEFI booting..."

    # Stage BOOTX64.EFI for size calculation, then build the FAT ESP image.
    # _make_efibootimg() sizes the image from efiboot_files[] and creates
    # the EFI/BOOT directory structure inside the image.
    efiboot_files+=('/usr/share/limine/BOOTX64.EFI')
    _make_efibootimg

    # Copy Limine's UEFI binary into the FAT ESP at the standard fallback path.
    mcopy -i "${efibootimg}" /usr/share/limine/BOOTX64.EFI '::/EFI/BOOT/BOOTX64.EFI'

    # Also copy into ISO 9660 so a user can manually partition a disk and copy
    # the ISO tree; the UEFI firmware will find BOOTX64.EFI at EFI/BOOT/.
    install -d -m 0755 -- "${isofs_dir}/EFI/BOOT"
    install -m 0644 -- /usr/share/limine/BOOTX64.EFI "${isofs_dir}/EFI/BOOT/BOOTX64.EFI"

    _make_limine_iso_config
    _msg_info "Done! Limine set up for UEFI booting."
}

_add_xorrisofs_options_uefi.limine() {
    # Attaches efibootimg as GPT partition 2 (EFI system partition) and adds
    # an El Torito UEFI boot entry pointing to that partition.
    # Uses the same helper as uefi.systemd-boot and uefi.grub so the hybrid
    # GPT/MBR layout is set up correctly.
    _add_common_xorrisofs_options_uefi
}
