#!/usr/bin/env bash
# =============================================================================
# mainstream-postinstall-common.sh — shared helpers, limine funcs + MAIN_USER (sourced by post-install-* steps)
# =============================================================================

set -euo pipefail

# Merge stderr into stdout so every message — including output from subprocesses
# like uv, find, ls, and sed — appears in the Calamares log in order.
# Calamares captures the shellprocess stdout; without this, stderr lines are
# either interleaved unpredictably or dropped entirely depending on the version.
exec 2>&1

log()  { echo "[post-install] $*"; }
info() { log "INFO:  $*"; }
warn() { log "WARN:  $*"; }


write_limine_defaults() {
    mkdir -p /etc/default
    cat > /etc/default/limine << 'LIMINEDEF'
TARGET_OS_NAME="Mainstream OS\\"
FIND_BOOTLOADERS=no
SNAPPER_CONFIG_NAME=root
ENABLE_UKI=yes
CUSTOM_UKI_NAME="mainstream"
LIMINEDEF
}

# NOTE: refresh_limine_uki_entry was removed. limine-mkinitcpio-hook owns the
# single branded "/+Mainstream OS\\" entry (machine-id tracked, with the real
# UKI hash + cmdline), so hand-writing a "/Mainstream OS\\" entry only produced
# a hash-less duplicate (the hook's entry starts "/+", which the old awk never
# matched). The branded entry now comes straight from the hook; see the prune +
# brand step after limine-mkinitcpio below.

parse_disk_part_from_source() {
    local source="$1"

    if [[ "$source" =~ ^(/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
        printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$source" =~ ^(/dev/mmcblk[0-9]+)p([0-9]+)$ ]]; then
        printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$source" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
        printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        return 1
    fi
}

cleanup_limine_boot_entries() {
    local esp_path=""
    local label="Mainstream"
    local loader_path="\\EFI\\limine\\BOOTX64.EFI"
    local loader_path_normalized="/efi/limine/bootx64.efi"

    [[ -d /boot/efi ]] && esp_path="/boot/efi"
    [[ -z "$esp_path" && -d /boot ]] && esp_path="/boot"
    [[ -n "$esp_path" ]] || { warn "No ESP mount found — skipping boot entry cleanup."; return 0; }

    write_limine_defaults

    if [[ -d "$esp_path/EFI" ]]; then
        info "Removing stale fallback and old bootloader files from $esp_path..."
        rm -rf \
            "$esp_path/EFI/BOOT" \
            "$esp_path/EFI/grub" \
            "$esp_path/EFI/GRUB" \
            "$esp_path/EFI/systemd" \
            "$esp_path/EFI/refind" \
            "$esp_path/loader" \
            "$esp_path/grub" \
            2>/dev/null || true
    fi

    if [[ -f "$esp_path/EFI/Linux/mainstream_linux.efi" ]]; then
        rm -f \
            "$esp_path/vmlinuz-linux" \
            "$esp_path/initramfs-linux.img" \
            "$esp_path/initramfs-linux-fallback.img" \
            2>/dev/null || true
    fi

    command -v efibootmgr >/dev/null 2>&1 || { warn "efibootmgr not found — skipping NVRAM cleanup."; return 0; }

    local source part_uuid disk part
    source=$(findmnt -n -o SOURCE "$esp_path" 2>/dev/null) || { warn "findmnt failed for $esp_path — skipping NVRAM cleanup."; return 0; }
    part_uuid=$(findmnt -n -o PARTUUID "$esp_path" 2>/dev/null) || { warn "PARTUUID lookup failed for $esp_path — skipping NVRAM cleanup."; return 0; }
    [[ -n "$part_uuid" ]] || { warn "Empty PARTUUID for $esp_path — skipping NVRAM cleanup."; return 0; }

    read -r disk part < <(parse_disk_part_from_source "$source") || {
        warn "Could not parse disk/partition from $source — skipping NVRAM cleanup."
        return 0
    }

    local efibootmgr_output line bootnum normalized keep_existing=false
    efibootmgr_output=$(efibootmgr -v 2>/dev/null) || { warn "efibootmgr read failed — skipping NVRAM cleanup."; return 0; }

    while IFS= read -r line; do
        [[ "$line" =~ ^Boot([0-9A-Fa-f]{4})\*?[[:space:]] ]] || continue
        bootnum="${BASH_REMATCH[1]}"
        grep -Fqi "$part_uuid" <<< "$line" || continue

        normalized="$(tr '[:upper:]' '[:lower:]' <<< "$line" | tr '\\' '/')"

        if grep -Eqi "^Boot${bootnum}\\*?[[:space:]]+${label}[[:space:]]" <<< "$line" \
                && [[ "$normalized" == *"$loader_path_normalized"* ]]; then
            if $keep_existing; then
                efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
            else
                keep_existing=true
            fi
            continue
        fi

        case "$normalized" in
            *"/efi/limine/bootx64.efi"*|*"/efi/boot/bootx64.efi"*|*"/efi/grub/"*|*"/efi/systemd/"*|*"/efi/refind/"*|*"/shimx64.efi"*|*"/grubx64.efi"*|*"/systemd-bootx64.efi"*)
                efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
                ;;
        esac

        # Also delete any entry labelled bare "Limine" (the default label that
        # limine-install uses) regardless of path — these are stale live-ISO entries.
        if grep -Eqi "^Boot${bootnum}\*?[[:space:]]+Limine[[:space:]]" <<< "$line"; then
            efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
        fi
    done <<< "$efibootmgr_output"

    if ! $keep_existing; then
        if efibootmgr --create \
            --disk "$disk" \
            --part "$part" \
            --label "$label" \
            --loader "$loader_path" \
            --unicode >/dev/null 2>&1; then
            info "Created single NVRAM entry '$label' for $loader_path (PARTUUID=$part_uuid)."
        else
            warn "Failed to create '$label' NVRAM entry."
        fi
    else
        info "Kept single NVRAM entry '$label' for Limine."
    fi
}

# ---------------------------------------------------------------------------
# 1. IDENTIFY USERS (SAFETY CHECK)
# ---------------------------------------------------------------------------
# Identify the actual user created by Calamares (UID 1000)
MAIN_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 <= 1001 {print $1}' | grep -vE '(liveuser|builduser|nobody|root)' | head -n 1 || true)
MAIN_USER_HOME="/home/$MAIN_USER"
