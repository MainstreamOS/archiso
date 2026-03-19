#!/usr/bin/env bash
# =============================================================================
# build.sh — Build the Mainstream Hyprland archiso with Limine bootloader
# =============================================================================
# Usage:
#   sudo ./build.sh [options]
#
# Options:
#   -v          Verbose output from mkarchiso
#   -c          Clear the work directory before building
#   -o <dir>    Output directory  (default: ./out)
#   -w <dir>    Work directory    (default: ./work)
#
# How it works:
#   1. Prepends Limine bootmode functions (configs/hyprland-dotfiles/bootmodes/limine.sh)
#      into a temporary copy of archiso/mkarchiso (right after the shebang) so
#      that mkarchiso's dynamic function dispatch picks up _make_bootmode_bios.limine
#      and friends before _validate_options / _build are executed.
#   2. Runs the patched mkarchiso to build the ISO.
#   3. Runs `limine bios-install <iso>` to embed Limine's MBR bootstrap code
#      so the ISO is bootable from USB via BIOS as well as CD/DVD.
#
# Requirements (build host):
#   pacman -S limine dosfstools mtools xorriso squashfs-tools erofs-utils

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${SCRIPT_DIR}/configs/hyprland-dotfiles"
MKARCHISO="${SCRIPT_DIR}/archiso/mkarchiso"
LIMINE_BOOTMODES="${PROFILE_DIR}/bootmodes/limine.sh"

OUT_DIR="${SCRIPT_DIR}/out"
WORK_DIR="${SCRIPT_DIR}/work"
VERBOSE=""
CLEAR_WORK=0

# ── Argument parsing ────────────────────────────────────────────────────────
while getopts 'vco:w:' opt; do
    case "${opt}" in
        v) VERBOSE='-v' ;;
        c) CLEAR_WORK=1 ;;
        o) OUT_DIR="${OPTARG}" ;;
        w) WORK_DIR="${OPTARG}" ;;
        *) echo "Usage: sudo $0 [-v] [-c] [-o out_dir] [-w work_dir]" >&2; exit 1 ;;
    esac
done

# ── Root check ──────────────────────────────────────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: ${0##*/} must be run as root (mkarchiso requires root)." >&2
    exit 1
fi

# ── Dependency check ────────────────────────────────────────────────────────
for _bin in limine mkfs.fat mmd mcopy xorriso mksquashfs; do
    if ! command -v "${_bin}" &>/dev/null; then
        echo "ERROR: '${_bin}' not found. Install it on the build host." >&2
        exit 1
    fi
done

for _f in /usr/share/limine/limine-bios-cd.bin \
           /usr/share/limine/limine-bios.sys \
           /usr/share/limine/BOOTX64.EFI; do
    if [[ ! -f "${_f}" ]]; then
        echo "ERROR: ${_f} not found. Install 'limine' on the build host." >&2
        exit 1
    fi
done

# ── Work directory ──────────────────────────────────────────────────────────
if (( CLEAR_WORK )) && [[ -d "${WORK_DIR}" ]]; then
    echo ">>> Clearing work directory: ${WORK_DIR}"
    rm -rf -- "${WORK_DIR}"
fi

mkdir -p -- "${OUT_DIR}" "${WORK_DIR}"

# ── Patch mkarchiso with Limine bootmode functions ──────────────────────────
# mkarchiso defines all bootmode functions internally and calls _build at the
# very end of the script.  Appending our functions AFTER that call means bash
# hasn't parsed them yet when _validate_options runs typeset -f.
#
# Fix: prepend our functions immediately after the shebang so they are
# defined before any execution code runs, while still having access to
# mkarchiso's helper functions (_msg_info, _make_efibootimg, etc.) because
# those functions are only CALLED (not needed) at definition time.
PATCHED_MKARCHISO="$(mktemp /tmp/mkarchiso-limine-XXXXXX)"
trap 'rm -f -- "${PATCHED_MKARCHISO}"' EXIT
chmod +x -- "${PATCHED_MKARCHISO}"

{
    # Line 1: shebang (#!/usr/bin/env bash)
    head -1 "${MKARCHISO}"
    # Limine bootmode function definitions — inserted right after shebang
    cat -- "${LIMINE_BOOTMODES}"
    # Rest of mkarchiso (skip the shebang we already wrote)
    tail -n +2 "${MKARCHISO}"
} > "${PATCHED_MKARCHISO}"

echo ">>> Building ISO (this takes several minutes)..."
"${PATCHED_MKARCHISO}" \
    ${VERBOSE} \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"

# ── Find the output ISO ──────────────────────────────────────────────────────
ISO_PATH="$(ls -t "${OUT_DIR}"/*.iso 2>/dev/null | head -1)"
if [[ -z "${ISO_PATH}" ]]; then
    echo "ERROR: No ISO found in ${OUT_DIR} after build." >&2
    exit 1
fi
echo ">>> ISO created: ${ISO_PATH}"

# ── Embed Limine BIOS bootstrap for USB hybrid boot ─────────────────────────
# limine bios-install patches the ISO's MBR area so the image is also bootable
# via BIOS when written to a USB drive (isohybrid-style).
# The limine-bios.sys file embedded in the ISO (by bios.limine bootmode) must
# be present for this step to succeed.
echo ">>> Embedding Limine BIOS bootstrap (limine bios-install)..."
limine bios-install "${ISO_PATH}"

echo ""
echo "Build complete."
echo "Output: ${ISO_PATH}"
echo ""
echo "Write to USB:  dd if='${ISO_PATH}' of=/dev/sdX bs=4M status=progress"
