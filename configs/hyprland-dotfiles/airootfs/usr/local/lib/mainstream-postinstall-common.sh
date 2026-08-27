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
