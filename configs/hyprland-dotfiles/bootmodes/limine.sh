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

# The live medium is built with the upstream Limine binary selected by build.sh.
# Keep an exact copy in the airootfs so install-limine can put that same binary
# on the target ESP. Previously the installed system used whatever version the
# Arch `limine` package happened to provide, while the ISO used a newer upstream
# binary. That made firmware compatibility differ between a live boot and the
# resulting installation.
_stage_limine_efi_for_installer() {
    local _source="${LIMINE_DIR:-/usr/share/limine}/BOOTX64.EFI"
    local _destination="${pacstrap_dir}/usr/local/share/mainstream/limine/BOOTX64.EFI"

    [[ -f "${_source}" ]] || {
        _msg_error "Cannot stage Limine for the installed system: ${_source} is missing." 1
        return 1
    }
    install -D -m 0644 -- "${_source}" "${_destination}"
}

# Copy CPU microcode images alongside the kernel + initramfs that
# mkarchiso's _make_boot_on_iso9660 already placed in
# ${isofs_dir}/${install_dir}/boot/${arch}/. The Limine boot entries
# reference both intel-ucode.img and amd-ucode.img as initrd lines —
# the CPU loads whichever matches its vendor and ignores the other —
# so both files must be present on the ISO regardless of build host
# vendor. mkarchiso doesn't copy microcode by default; each bootmode
# is responsible for installing the files it references. Without
# this, Limine panics at "Failed to open module with path
# 'boot():///arch/boot/x86_64/intel-ucode.img'" on every entry.
#
# Source path: this mkarchiso version doesn't expose ${airootfs_dir}
# as a variable in the bootmode function context (the older
# convention used ${pacstrap_dir}, newer versions ${airootfs_dir}).
# Use the always-stable concatenation ${work_dir}/${arch}/airootfs
# instead — that's what mkarchiso pacstraps into and what
# _make_boot_on_iso9660 reads its kernel+initramfs from, regardless
# of mkarchiso version.
#
# Guarded against double-copy if both bios.limine and uefi.limine
# are active — the second call is a no-op when the destination
# already has the files.
_install_limine_microcode() {
    local _boot_dir="${isofs_dir}/${install_dir}/boot/${arch}"
    local _src_dir="${work_dir}/${arch}/airootfs/boot"
    [[ -d "${_boot_dir}" ]] || return
    local _uc
    for _uc in intel-ucode.img amd-ucode.img; do
        if [[ -e "${_src_dir}/${_uc}" && ! -e "${_boot_dir}/${_uc}" ]]; then
            install -m 0644 -- "${_src_dir}/${_uc}" "${_boot_dir}/${_uc}"
        fi
    done
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
    for _f in "${LIMINE_DIR:-/usr/share/limine}/limine-bios-cd.bin" "${LIMINE_DIR:-/usr/share/limine}/limine-bios.sys"; do
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
    install -m 0644 -- "${LIMINE_DIR:-/usr/share/limine}/limine-bios-cd.bin" "${isofs_dir}/limine-bios-cd.bin"
    # Limine BIOS system binary (needed by limine bios-install for USB hybrid)
    install -m 0644 -- "${LIMINE_DIR:-/usr/share/limine}/limine-bios.sys" "${isofs_dir}/limine-bios.sys"
    _make_limine_iso_config
    _install_limine_microcode
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
    for _f in "${LIMINE_DIR:-/usr/share/limine}/BOOTX64.EFI"; do
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

    # Do this before _cleanup_pacstrap_dir()/the squashfs build. The installed
    # system uses this staged upstream image instead of a possibly older distro
    # package copy.
    _stage_limine_efi_for_installer

    # Stage BOOTX64.EFI for size calculation, then build the FAT ESP image.
    # _make_efibootimg() only sizes and formats the image — it creates no
    # directories inside it. It used to, via `mmd ::/EFI ::/EFI/BOOT`, until
    # upstream de9c6bb ("mkarchiso: reduce the number of mcopy commands")
    # replaced the per-file copies with a recursive `mcopy -s ... ::/` that
    # makes directories as it walks. This bootmode copies a single file to a
    # nested path, so it has to create that path itself or mcopy aborts the
    # build with "Bad target ::/EFI/BOOT/BOOTX64.EFI".
    efiboot_files+=("${LIMINE_DIR:-/usr/share/limine}/BOOTX64.EFI")
    _make_efibootimg

    # Copy Limine's UEFI binary into the FAT ESP at the standard fallback path.
    mmd -i "${efibootimg}" '::/EFI' '::/EFI/BOOT'
    mcopy -i "${efibootimg}" "${LIMINE_DIR:-/usr/share/limine}/BOOTX64.EFI" '::/EFI/BOOT/BOOTX64.EFI'

    # Also copy into ISO 9660 so a user can manually partition a disk and copy
    # the ISO tree; the UEFI firmware will find BOOTX64.EFI at EFI/BOOT/.
    install -d -m 0755 -- "${isofs_dir}/EFI/BOOT"
    install -m 0644 -- "${LIMINE_DIR:-/usr/share/limine}/BOOTX64.EFI" "${isofs_dir}/EFI/BOOT/BOOTX64.EFI"

    _make_limine_iso_config
    _install_limine_microcode
    _msg_info "Done! Limine set up for UEFI booting."
}

_add_xorrisofs_options_uefi.limine() {
    # Attaches efibootimg as GPT partition 2 (EFI system partition) and adds
    # an El Torito UEFI boot entry pointing to that partition.
    # Uses the same helper as uefi.systemd-boot and uefi.grub so the hybrid
    # GPT/MBR layout is set up correctly.
    _add_common_xorrisofs_options_uefi
}
