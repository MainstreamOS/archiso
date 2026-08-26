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
warn() { log "WARN:  $*"; _ms_health "WARN: $*"; }

# Persistent install-health manifest on the target. The Calamares session log
# lives on the live system and its shellprocess stdout capture is lossy, so
# every warn is also appended here — the installed system keeps a record of
# what the install steps could not do.
_ms_health() {
    mkdir -p /var/log/mainstream-install 2>/dev/null || return 0
    printf '%s [%s] %s\n' "$(date '+%F %T')" "${0##*/}" "$*" \
        >> /var/log/mainstream-install/health.log 2>/dev/null || true
}


write_limine_defaults() {
    mkdir -p /etc/default
    # Probing is on so another system sharing the disk shows up on its own.
    # It finds systemd-boot and rEFInd; Windows it never looks for, which is why
    # that one is registered by hand further along. The catch is the generic
    # fallback loader: EFI/BOOT/BOOTX64.EFI is Limine itself here, so probing
    # offers an entry that boots the menu back into the menu. The install prunes
    # that one, though probing runs again whenever the entries are regenerated,
    # so it can return after a kernel update until something prunes it there too.
    cat > /etc/default/limine << 'LIMINEDEF'
TARGET_OS_NAME="Mainstream OS\\"
FIND_BOOTLOADERS=yes
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

    mountpoint -q /boot/efi && esp_path="/boot/efi"
    [[ -z "$esp_path" && -d /boot ]] && esp_path="/boot"
    [[ -n "$esp_path" ]] || { warn "No ESP mount found — skipping boot entry cleanup."; return 0; }

    write_limine_defaults

    if [[ -d "$esp_path/EFI" ]]; then
        info "Removing stale old bootloader files from $esp_path..."
        rm -rf \
            "$esp_path/EFI/grub" \
            "$esp_path/EFI/GRUB" \
            "$esp_path/EFI/systemd" \
            "$esp_path/EFI/refind" \
            "$esp_path/loader" \
            "$esp_path/grub" \
            2>/dev/null || true
    fi

    # EFI/BOOT/BOOTX64.EFI is the UEFI-defined removable-media fallback. Some
    # firmware boots it when it ignores or loses an NVRAM entry, so it is part
    # of the installed boot chain and must never be cleaned up.
    if [[ ! -f "$esp_path/EFI/BOOT/BOOTX64.EFI" && -f "$esp_path/EFI/limine/BOOTX64.EFI" ]]; then
        install -Dm0644 "$esp_path/EFI/limine/BOOTX64.EFI" "$esp_path/EFI/BOOT/BOOTX64.EFI"
        info "Restored Limine's UEFI fallback loader."
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

# The version both halves of the ABI guard are stamped with. pacman first
# because it reports pkgrel and pkg-config does not; a pkgrel-only rebuild
# changes the plugin ABI while the bare version stays put. Kept identical to
# /usr/lib/mainstream/*/rebuild.sh — the guard in custom/general.lua compares
# what they write, so a format that drifts between them fails closed.
hyprland_stamp_version() {
    local _v
    _v=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
    [[ -n "$_v" ]] || _v=$(pkg-config --modversion hyprland 2>/dev/null || echo "")
    printf '%s' "$_v"
}

# Record which Hyprland the installed system runs. The ISO bakes a value from
# its own build host; this overwrites it with the target's ground truth.
record_hyprland_version() {
    local _v
    _v=$(hyprland_stamp_version)
    [[ -n "$_v" ]] || { warn "Could not read Hyprland version — plugin ABI guard left unarmed."; return 0; }
    mkdir -p /var/lib/hyprland-plugins
    printf '%s\n' "$_v" > /var/lib/hyprland-plugins/hyprland-version
    info "Recorded Hyprland $_v for the plugin ABI guard."
}

build_hyprland_plugin() {
    local name="$1"
    local repo_url="$2"
    local branch="$3"
    local make_subdir="$4"
    local so_filename="$5"
    local directive_commented="$6"
    shift 6
    local _deps=("$@")

    local _PLUGIN_DATA_DIR="$MAIN_USER_HOME/.local/share/hyprland/plugins"
    local _PLUGIN_PATH="$_PLUGIN_DATA_DIR/$so_filename"
    local _GENERAL_LUA="$MAIN_USER_HOME/.config/hypr/custom/general.lua"
    local _BUILD_LOG="$_PLUGIN_DATA_DIR/$name-build.log"
    local _SRC_DIR
    _SRC_DIR="$(mktemp -d "/tmp/$name-build.XXXXXX")"

    local _make_dir="$_SRC_DIR"
    [[ -n "$make_subdir" ]] && _make_dir="$_SRC_DIR/$make_subdir"

    local _missing_deps=()
    local _pc
    for _pc in "${_deps[@]}"; do
        pkg-config --exists "$_pc" 2>/dev/null || _missing_deps+=("$_pc")
    done
    if (( ${#_missing_deps[@]} > 0 )); then
        warn "Missing pkg-config deps for $name: ${_missing_deps[*]}"
        warn "Install the corresponding -devel packages and re-run the installer."
        warn "Skipping $name build — plugin will not be available on first boot."
        rm -rf "$_SRC_DIR"
    else
        mkdir -p "$_PLUGIN_DATA_DIR"
        mkdir -p "$(dirname "$_BUILD_LOG")"

        {
            echo "=== $name build @ $(date '+%Y-%m-%d %H:%M:%S') ==="
            echo "Build host: $(uname -r)"
            echo "---"
        } > "$_BUILD_LOG"

        info "Cloning $repo_url ($branch) into $_SRC_DIR..."
        if ! git -C "$_SRC_DIR" clone --depth=1 --branch "$branch" "$repo_url" . \
                >> "$_BUILD_LOG" 2>&1; then
            warn "git clone failed — check network and retry. Build log: $_BUILD_LOG"
            rm -rf "$_SRC_DIR"
        else
            echo "Plugin commit: $(git -C "$_SRC_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
                >> "$_BUILD_LOG"

            info "Compiling $name ($(nproc) jobs)..."
            if ! make -C "$_make_dir" all -j"$(nproc)" >> "$_BUILD_LOG" 2>&1; then
                warn "$name make failed — build log: $_BUILD_LOG"
                rm -rf "$_SRC_DIR"
            else
                cp -f "$_make_dir/$so_filename" "$_PLUGIN_PATH"
                printf '%s\n' "$(hyprland_stamp_version)" > "$_PLUGIN_PATH.builtfor"
                info "Installed $so_filename to $_PLUGIN_PATH"
                rm -rf "$_SRC_DIR"

                if [[ -f "$_GENERAL_LUA" ]]; then
                    if ! grep -qE "hl\.plugin\.load.*$so_filename" "$_GENERAL_LUA"; then
                        local _tmp
                        _tmp=$(mktemp)
                        {
                            if [[ "$directive_commented" == "true" ]]; then
                                echo "-- $name plugin — built from source at install time"
                                echo "-- TitleBars.qml toggles the comment prefix on this exact line."
                                echo "-- hl.plugin.load(\"${_PLUGIN_PATH}\")"
                            else
                                echo "-- $name plugin — built from source at install time"
                                echo "hl.plugin.load(\"${_PLUGIN_PATH}\")"
                            fi
                            echo ""
                            cat "$_GENERAL_LUA"
                        } > "$_tmp"
                        mv "$_tmp" "$_GENERAL_LUA"
                        info "Prepended hl.plugin.load(\"${_PLUGIN_PATH}\") to $_GENERAL_LUA"
                    else
                        info "$_GENERAL_LUA already references $name — skipping directive."
                    fi
                else
                    warn "$_GENERAL_LUA not found — add this line manually to a sourced hypr config:"
                    warn "  hl.plugin.load(\"${_PLUGIN_PATH}\")"
                fi
            fi
        fi

        chown -R "$MAIN_USER:$MAIN_USER" "$_PLUGIN_DATA_DIR" 2>/dev/null || true
        [[ -f "$_GENERAL_LUA" ]] && \
            chown "$MAIN_USER:$MAIN_USER" "$_GENERAL_LUA" 2>/dev/null || true
        info "Ownership of plugin directory set to $MAIN_USER."
    fi
}

# ---------------------------------------------------------------------------
# 1. IDENTIFY USERS (SAFETY CHECK)
# ---------------------------------------------------------------------------
# Identify the actual user created by Calamares (UID 1000)
MAIN_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 <= 1001 {print $1}' | grep -vE '(liveuser|builduser|nobody|root)' | head -n 1 || true)
MAIN_USER_HOME="/home/$MAIN_USER"
