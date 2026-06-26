#!/usr/bin/env bash
# =============================================================================
# build.sh — Build the Mainstream Hyprland archiso with Limine bootloader
# =============================================================================
# Usage:
#   sudo ./build.sh [options]
#
# Options:
#   -v              Verbose output from mkarchiso
#   -c              Clear the work directory before building
#   -o <dir>        Output directory  (default: ./out)
#   -w <dir>        Work directory    (default: ./work)
#   --refresh       Rebuild packages (skip unchanged), then build ISO
#   --clean         Remove all pre-built packages and rebuild from scratch, then build ISO
#   --cleancal      Remove calamares-mainstream package and rebuild it, then build ISO
#
# If --refresh, --clean, or --cleancal is passed the package-build phase runs
# first, then the ISO build follows.
# Without those flags, only the ISO build runs (packages must already exist).
#
# How it works:
#   1. (Optional) Builds pre-compiled .pkg.tar.zst meta-packages, AUR deps,
#      skel dotfiles, and Python venv — depositing them into
#      configs/hyprland-dotfiles/airootfs/usr/local/share/pkgs/
#   2. Prepends Limine bootmode functions into a temporary copy of mkarchiso.
#   3. Runs the patched mkarchiso to build the ISO.
#   4. Runs `limine bios-install <iso>` to embed Limine's MBR bootstrap code.
#
# Requirements (build host):
#   pacman -S limine dosfstools mtools xorriso squashfs-tools erofs-utils

set -euo pipefail

# Speed up package builds by using all available CPU cores
export MAKEFLAGS="-j$(nproc)"

# Speed up package compression using multi-threaded zstd
export COMPRESSZST=(zstd -c -z -q -T0 -)



# =============================================================================
# HELPERS
# =============================================================================
log()     { echo "[build] $*"; }
info()    { log "INFO:  $*"; }
warn()    { log "WARN:  $*"; }
die()     { log "FATAL: $*"; exit 1; }
success() { log "OK:    $*"; }

# Build the [mainstream] local repo DB from <repo_dir>, EXCLUDING GPU driver
# packages. The nvidia / opencl-nvidia / lib32-nvidia / libxnvctrl packages
# still ship as plain files in the airootfs — install-gpu-drivers pacman -U's
# them by PCI match at install time — but they must NOT appear in the repo DB:
# otherwise mkarchiso's pacstrap auto-selects one to satisfy the generic
# opengl-driver / vulkan-driver / nvidia-utils provide pulled in by the
# hyprland/aquamarine stack (and [mainstream] is first in pacman.conf), baking
# an nvidia driver into AMD/Intel-only ISOs.
add_mainstream_db() {
    local repo_dir="$1"
    # Debug packages are never installed (not in packages.x86_64); drop any an
    # earlier build left here so they neither index nor bloat the live squashfs.
    rm -f "$repo_dir"/*-debug-*.pkg.tar.zst 2>/dev/null || true
    # repo-add only ADDS — start from a clean DB so any previously-indexed
    # (and now-excluded) GPU driver entries are dropped, not carried forward.
    rm -f "$repo_dir"/mainstream.db{,.tar.gz,.tar.gz.old} \
          "$repo_dir"/mainstream.files{,.tar.gz,.tar.gz.old}
    local pkgs=()
    mapfile -t pkgs < <(find "$repo_dir" -maxdepth 1 -type f -name '*.pkg.tar.zst' \
        ! -name '*nvidia*' ! -name 'libxnvctrl*' ! -name '*-debug-*' | sort)
    # Legacy-NVIDIA edition: pacstrap must resolve the live driver, so add
    # nvidia-580xx-{dkms,utils} back in. Other gens stay files-only (target-only
    # via install-gpu-drivers); excluding them avoids provide-ambiguity. The
    # [0-9] pins the version segment so debug/lib32-/opencl- names don't match.
    if [[ "${NVIDIA_PROFILE:-false}" == true ]]; then
        local nvpkgs=()
        mapfile -t nvpkgs < <(find "$repo_dir" -maxdepth 1 -type f \
            \( -name 'nvidia-580xx-dkms-[0-9]*.pkg.tar.zst' \
               -o -name 'nvidia-580xx-utils-[0-9]*.pkg.tar.zst' \) \
            ! -name '*-debug-*' | sort)
        pkgs+=("${nvpkgs[@]}")
    fi
    if (( ${#pkgs[@]} == 0 )); then
        warn "No installable (non-GPU-driver) packages in $repo_dir — mainstream repo DB not created."
        return 0
    fi
    repo-add "$repo_dir/mainstream.db.tar.gz" "${pkgs[@]}"
}

# ── Legacy-NVIDIA edition overlay ───────────────────────────────────────────
# --nvidia: from the same profile, swap the Turing+ live driver for the
# nvidia-580xx stack + dkms (packages.x86_64) and rename the ISO (profiledef.sh).
# The 580xx module builds against the live kernel via dkms's pacstrap hook (no
# GSP firmware → stays out of the init). Backed up + restored on ANY exit (trap)
# so the tree and later standard builds aren't mutated.
_OVERLAY_ARCHISO_CONF="airootfs/etc/mkinitcpio.conf.d/archiso.conf"
apply_profile_overlay() {
    [[ "${NVIDIA_PROFILE:-false}" == true ]] || return 0
    _OVERLAY_BAK_DIR="$(mktemp -d /tmp/nvidia-overlay-bak-XXXXXX)"
    cp -a "${PROFILE_DIR}/packages.x86_64" "$_OVERLAY_BAK_DIR/"
    cp -a "${PROFILE_DIR}/profiledef.sh"   "$_OVERLAY_BAK_DIR/"
    cp -a "${PROFILE_DIR}/${_OVERLAY_ARCHISO_CONF}" "$_OVERLAY_BAK_DIR/archiso.conf"
    sed -i -e 's/^nvidia-open$/nvidia-580xx-dkms/' \
           -e 's/^nvidia-utils$/nvidia-580xx-utils\ndkms/' \
           "${PROFILE_DIR}/packages.x86_64"
    # iso_name is a whole-line replace (idempotent); the iso_label pattern
    # tolerates an existing NV_ so a re-apply can't compound to MAINSTREAM_NV_NV_.
    sed -i -e 's/^iso_name=.*/iso_name="mainstreamos-desktop-linux-nvidia"/' \
           -e 's/^iso_label="MAINSTREAM_\(NV_\)\?/iso_label="MAINSTREAM_NV_/' \
           "${PROFILE_DIR}/profiledef.sh"
    # Early KMS for the legacy card so Plymouth has a DRM device from the start
    # (no post-pivot black screen). nvidia-gsp-strip drops the GSP firmware the
    # MODULES= add would otherwise bundle (580xx is GSP-free at runtime), so the
    # init stays small. Both seds are idempotent (whole-line MODULES; optional
    # ` nvidia-gsp-strip` after modconf).
    sed -i -e 's/^MODULES=.*/MODULES=(amdgpu i915 radeon nvidia nvidia_modeset nvidia_drm)/' \
           -e 's/modconf\( nvidia-gsp-strip\)\?/modconf nvidia-gsp-strip/' \
           "${PROFILE_DIR}/${_OVERLAY_ARCHISO_CONF}"
    info "Legacy-NVIDIA overlay applied: nvidia-580xx live driver + early KMS; iso_name → mainstreamos-desktop-linux-nvidia."
}

restore_profile_overlay() {
    [[ -n "${_OVERLAY_BAK_DIR:-}" && -d "${_OVERLAY_BAK_DIR:-}" ]] || return 0
    # Restore all three even if one fails (never leave a half-overlaid tree),
    # keep the backup on error, and always return 0 so trap cleanup continues.
    local rc=0
    cp -a "$_OVERLAY_BAK_DIR/packages.x86_64" "${PROFILE_DIR}/packages.x86_64" || rc=1
    cp -a "$_OVERLAY_BAK_DIR/profiledef.sh"   "${PROFILE_DIR}/profiledef.sh"   || rc=1
    cp -a "$_OVERLAY_BAK_DIR/archiso.conf"    "${PROFILE_DIR}/${_OVERLAY_ARCHISO_CONF}" || rc=1
    if (( rc == 0 )); then
        rm -rf -- "$_OVERLAY_BAK_DIR"
        _OVERLAY_BAK_DIR=""
    else
        warn "Profile overlay restore hit errors — backup kept at $_OVERLAY_BAK_DIR (restore packages.x86_64 + profiledef.sh from there)."
    fi
    return 0
}

# Pull the packages the GitHub [mainstream] repo already provides into the local
# repo, instead of rebuilding them here. The MainstreamOS/packages CI builds the
# FOSS packages (topgrade, the fonts, nautilus/mpv extensions, limine hooks, …)
# on its own schedule; rebuilding them AGAIN at ISO-build time grabs whatever
# AUR has *now*, so a fresh install can end up with a package NEWER than the
# repo. After the first-boot repoint that shows "local is newer than mainstream"
# and blocks updates. Downloading the repo's own builds makes the ISO ship
# byte-identical versions (no drift) and skips the recompile. Populates the
# global GITHUB_PROVIDED set; the AUR_DEPS loop skips any name in it. Anything
# the repo doesn't provide — or if GitHub is unreachable — falls through to the
# local build (curl --retry hardens the single-server GitHub fetch).
declare -A GITHUB_PROVIDED=()
download_mainstream_repo_pkgs() {
    local repo_dir="$1"
    local api="https://api.github.com/repos/MainstreamOS/packages/releases/tags/mainstream-repo"
    local rel="https://github.com/MainstreamOS/packages/releases/download/mainstream-repo"
    info "Fetching the [mainstream] GitHub repo package list..."
    # The release only ever ADDS assets, so it accumulates stale builds (dropped
    # or superseded packages). Trust the db, not the raw asset list: collect the
    # pkgname-ver-rel stems the current db indexes and pull only those.
    local current dbtmp
    dbtmp=$(mktemp)
    if curl -fsSL --retry 5 --retry-delay 4 --retry-connrefused -o "$dbtmp" "$rel/mainstream.db" 2>/dev/null; then
        current=$(tar tzf "$dbtmp" 2>/dev/null | grep -oE '^[^/]+/' | tr -d '/' | sort -u)
    fi
    rm -f "$dbtmp"
    local urls
    urls=$(curl -fsSL --retry 5 --retry-delay 4 --retry-connrefused "$api" 2>/dev/null \
        | grep -oE '"browser_download_url":[[:space:]]*"[^"]+\.pkg\.tar\.zst"' \
        | sed -E 's/.*"(https[^"]+)".*/\1/')
    if [[ -z "$urls" ]]; then
        warn "Could not list [mainstream] release assets — building every AUR package locally (versions may drift)."
        return 0
    fi
    local url f name base skip m stem
    while read -r url; do
        [[ -n "$url" ]] || continue
        base=$(basename "$url")
        # Skip assets the current db doesn't index — stale leftovers from old
        # builds. If the db fetch failed, fall back to downloading everything.
        if [[ -n "${current:-}" ]]; then
            stem=$(sed -E 's/-[^-]+\.pkg\.tar\.zst$//' <<< "$base")
            # Epoch packages publish a colon-free asset filename (GitHub Release
            # assets can't store the ':' epoch separator) while the db dir keeps
            # the epoch, so normalise ':'->'_' on the db side before matching —
            # otherwise the epoch package looks "stale" and falls back to a
            # drift-prone local build.
            if ! grep -qxF "$stem" <<< "${current//:/_}"; then
                info "$base — not in current db, skipping stale asset."
                continue
            fi
        fi
        # The mainstream-* meta-packages are compiled locally in this build,
        # against the Qt this ISO ships. Their published prebuilt is for the
        # script installer only (which has an ldd ABI fallback the offline ISO
        # lacks), so skip it here and keep the local build.
        skip=false
        for m in "${METAPKGS[@]}"; do
            [[ "$base" == "$m"-[0-9]* ]] && { skip=true; break; }
        done
        if [[ "$skip" == true ]]; then
            info "$base — built locally for the ISO, skipping prebuilt download."
            continue
        fi
        f="$repo_dir/$base"
        if curl -fL --retry 5 --retry-delay 4 --retry-connrefused -o "$f" "$url" 2>/dev/null; then
            name=$(pacman -Qpq "$f" 2>/dev/null || true)
            if [[ -n "$name" ]]; then
                GITHUB_PROVIDED["$name"]=1
                # Drop any older locally-built copy of the same package so the
                # repo db indexes only the GitHub version (no duplicate-name clash).
                find "$repo_dir" -maxdepth 1 -name "${name}-[0-9]*.pkg.tar.zst" \
                    ! -name "$(basename "$f")" -delete 2>/dev/null || true
            else
                warn "Downloaded $(basename "$f") but could not read its name — removing."
                rm -f "$f"
            fi
        else
            warn "Failed to download $(basename "$url") — will build it locally if needed."
            rm -f "$f"
        fi
    done <<< "$urls"
    info "Pulled ${#GITHUB_PROVIDED[@]} prebuilt package(s) from the [mainstream] GitHub repo."
}

# Scan a local pacman repo directory for corrupted / zero-length .pkg.tar.zst
# files, remove them, and regenerate the repo database so that subsequent
# pacman / mkarchiso runs don't trip over bad checksums.
#
# Usage: sanitize_local_repo <repo_dir>
sanitize_local_repo() {
    local repo_dir="$1"
    local removed=0
    local pkg

    if [[ ! -d "$repo_dir" ]]; then
        warn "sanitize_local_repo: directory not found: $repo_dir — skipping."
        return 0
    fi

    info "Checking local repo for corrupted packages: $repo_dir"

    for pkg in "$repo_dir"/*.pkg.tar.zst; do
        [[ -f "$pkg" ]] || continue   # no glob match → skip

        # Zero-length file — definitely corrupt
        if [[ ! -s "$pkg" ]]; then
            warn "  Removing zero-length package: $(basename "$pkg")"
            rm -f "$pkg"
            (( removed++ )) || true
            continue
        fi

        # Attempt to list the archive; any I/O or format error means corrupt.
        # Use -tf (no -z) so GNU tar auto-detects zstd compression; -tzf forces
        # gzip and incorrectly rejects every valid .pkg.tar.zst file.
        if ! tar -tf "$pkg" &>/dev/null; then
            warn "  Removing corrupted package: $(basename "$pkg")"
            rm -f "$pkg"
            (( removed++ )) || true
        fi
    done

    if (( removed > 0 )); then
        warn "$removed corrupted package(s) removed from $repo_dir."
        info "Regenerating repo database..."
        # Remove stale db files so repo-add starts clean
        rm -f "$repo_dir"/mainstream.db{,.tar.gz,.tar.gz.old} \
              "$repo_dir"/mainstream.files{,.tar.gz,.tar.gz.old} \
              "$repo_dir"/illogical-impulse.db{,.tar.gz,.tar.gz.old} \
              "$repo_dir"/illogical-impulse.files{,.tar.gz,.tar.gz.old}
        # Only call repo-add if at least one package still exists
        if compgen -G "$repo_dir/*.pkg.tar.zst" > /dev/null 2>&1; then
            add_mainstream_db "$repo_dir"
            success "Repo database regenerated."
        else
            warn "No packages remain in $repo_dir after sanitization — repo DB not created."
        fi
    else
        info "All packages passed integrity check."
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${SCRIPT_DIR}/configs/hyprland-dotfiles"
MKARCHISO="${SCRIPT_DIR}/archiso/mkarchiso"
LIMINE_BOOTMODES="${PROFILE_DIR}/bootmodes/limine.sh"

OUT_DIR="${SCRIPT_DIR}/out"
WORK_DIR="${SCRIPT_DIR}/work"
VERBOSE=""
CLEAR_WORK=0

# Package-build flags
REFRESH_PKGS=false
CLEAN_BUILD=false
CLEAN_CALAMARES=false
# Legacy-NVIDIA edition (--nvidia): also build the legacy NVIDIA prebuilts
# (NVIDIA_DEPS). Standard ISO omits them to stay slim.
NVIDIA_PROFILE=false
# Backup dir for the --nvidia profile overlay (set/cleared by apply/restore).
_OVERLAY_BAK_DIR=""

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
# Extract long options before getopts (which only handles short opts)
REMAINING_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --refresh)
            REFRESH_PKGS=true
            ;;
        --clean)
            CLEAN_BUILD=true
            REFRESH_PKGS=true   # --clean implies --refresh
            info "Clean build requested — all existing packages will be removed and rebuilt."
            ;;
        --cleancal)
            CLEAN_CALAMARES=true
            REFRESH_PKGS=true   # --cleancal implies --refresh
            info "Calamares clean requested — calamares-mainstream will be removed and rebuilt."
            ;;
        --nvidia)
            NVIDIA_PROFILE=true
            info "Legacy-NVIDIA edition requested — legacy NVIDIA prebuilts will be included."
            ;;
        --help|-h)
            cat <<'HELPEOF'
Usage: sudo ./build.sh [options]

ISO build options:
  -v              Verbose output from mkarchiso
  -c              Clear the work directory before building
  -o <dir>        Output directory  (default: ./out)
  -w <dir>        Work directory    (default: ./work)

Package build options:
  --refresh       Rebuild packages (skip unchanged), then build ISO
  --clean         Remove ALL pre-built packages and rebuild from scratch, then build ISO
  --cleancal      Remove calamares-mainstream package and rebuild it, then build ISO

Edition options:
  --nvidia        Build the legacy-NVIDIA edition: also includes the legacy
                  NVIDIA prebuilts for full accelerated support on pre-Turing
                  cards. Omit for the standard (slim) ISO.

Examples:
  sudo ./build.sh                     # ISO only (packages must already exist)
  sudo ./build.sh --refresh           # Rebuild packages + ISO
  sudo ./build.sh --clean -c          # Full clean rebuild (packages + work dir + ISO)
  sudo ./build.sh --cleancal          # Rebuild calamares + ISO
  sudo ./build.sh --refresh --nvidia  # Rebuild packages incl. legacy NVIDIA + ISO
HELPEOF
            exit 0
            ;;
        *)
            REMAINING_ARGS+=("$arg")
            ;;
    esac
done

# Re-set positional params for getopts
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

while getopts 'vco:w:' opt; do
    case "${opt}" in
        v) VERBOSE='-v' ;;
        c) CLEAR_WORK=1 ;;
        o) OUT_DIR="${OPTARG}" ;;
        w) WORK_DIR="${OPTARG}" ;;
        *) echo "Usage: sudo $0 [-v] [-c] [-o out_dir] [-w work_dir] [--refresh|--clean|--cleancal]" >&2; exit 1 ;;
    esac
done

# ── Root check ──────────────────────────────────────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: ${0##*/} must be run as root (mkarchiso requires root)." >&2
    exit 1
fi

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/MainstreamOS/dots-hyprland.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-mainstream}"

# #############################################################################
#
#   PHASE 1: PACKAGE BUILD  (only when --refresh / --clean / --cleancal)
#
# #############################################################################
if [[ "$REFRESH_PKGS" == true ]]; then

info "═══════════════════════════════════════════════════════════════"
info "  PHASE 1: Building packages"
info "═══════════════════════════════════════════════════════════════"
info "  [BUILD-DIAG] Build flags: REFRESH_PKGS=$REFRESH_PKGS  CLEAN_BUILD=$CLEAN_BUILD  CLEAN_CALAMARES=$CLEAN_CALAMARES"
info "  [BUILD-DIAG] Script dir: $SCRIPT_DIR"
info "  [BUILD-DIAG] Profile dir: $PROFILE_DIR"
info "  [BUILD-DIAG] DOTFILES_REPO: $DOTFILES_REPO  branch: $DOTFILES_BRANCH"

# ── Package-build config ────────────────────────────────────────────────────
PKG_OUTPUT_DIR="$PROFILE_DIR/airootfs/usr/local/share/pkgs"
PKG_WORK_DIR="/tmp/iso-pkg-build"
BUILD_USER="iso-builder"

METAPKGS=(
    "mainstream-audio"
    "mainstream-backlight"
    "mainstream-basic"
    "mainstream-fonts-themes"
    "mainstream-gnome"
    "mainstream-hyprland"
    "mainstream-portal"
    "mainstream-python"
    "mainstream-screencapture"
    "mainstream-toolkit"
    "mainstream-widgets"
    "mainstream-quickshell-git"
    "mainstream-extras"
    "mainstream-bibata-modern-classic-bin"
    "mainstream-gaming"
)
# mainstream-microtex-git is built separately below — its cmake source build
# needs makepkg -s (syncdeps) and --skippgpcheck, which the generic
# METAPKGS BUILD_SCRIPT (--nodeps) doesn't provide.

AUR_DEPS=(
    # Native Zen (default Firefox-fork browser), prebuilt into [mainstream] so
    # the netinstall installs it with plain `pacman -S` instead of a Flatpak
    # ref. A sandboxed Flatpak browser can't read /etc/<browser>/policies/ or
    # reach the native-messaging host, which silently breaks the
    # mpris-hyprland auto-install; the native build works out of the box.
    # (Firefox and Chromium are in the official repos, so they need no prebuild.)
    "zen-browser-bin"
    "ckbcomp"
    "ttf-google-sans"
    "limine-mkinitcpio-hook"
    "limine-snapper-sync"
    "topgrade"
    "wlogout"
    "adw-gtk-theme-git"
    "breeze-plus"
    "darkly-bin"
    "otf-space-grotesk::38c3-styles"
    "ttf-material-symbols-variable-git::material-symbols-git"
    "ttf-readex-pro"
    "ttf-rubik-vf"
    "ttf-twemoji"
    "qt6-avif-image-plugin::qt5-avif-image-plugin"

    # Default apps that were AUR-only and got dropped from netinstall when the
    # installer moved off yay. Prebuilt here so a plain `pacman -S` from
    # [mainstream] restores them on every fresh install — Nautilus right-click
    # extensions and mpv UI scripts (all FOSS, deps resolve from extra).
    "nautilus-copy-path"
    "nautilus-admin-gtk4"
    "mpv-modernz"
    "mpv-thumbfast-git"

    # Gaming Mode (Super+G) — the ChimeraOS/Open Gaming Collective gamescope
    # session stack that the Steam Deck, Bazzite and ChimeraOS all run. Prebuilt
    # into [mainstream]; the mainstream-gaming meta-package depends on these, so
    # a plain `pacman -S mainstream-gaming` pulls them (never from the AUR).
    # Both are arch=any pure file-install packages (makedepends=git only), so
    # the --nodeps loop builds them without pulling the gamescope runtime first;
    # gamescope-session-steam-git's dep on gamescope-session-git resolves from
    # [mainstream] at install time.
    "gamescope-session-git"
    "gamescope-session-steam-git"
)

# ── Legacy NVIDIA DKMS drivers (Pascal/Maxwell/Volta → Kepler → Fermi) ──
# Built ONLY for the legacy-NVIDIA edition (--nvidia), appended to AUR_DEPS
# below; the standard ISO omits them to stay slim.
#
# Arch's mainline `nvidia` package follows the current driver (590+ at time
# of writing) which drops Maxwell-Pascal-Volta support; the current
# `nvidia-open` covers Turing+ only. Older cards need the AUR legacy DKMS
# variants. Pre-building them here (against the build host's kernel headers —
# DKMS still rebuilds per-kernel at install time) lets install-gpu-drivers do
# a plain `pacman -U` from /usr/local/share/pkgs/ instead of
# yay-fetching-and-compiling from AUR inside the install chroot, which is
# unreliable (network + build-environment fragility inside Calamares' chroot).
#
# Trade-off: each generation's source tarball is ~600 MB during build; the
# resulting .pkg.tar.zst is ~50-100 MB and lives in the airootfs whether the
# install target needs it or not. Worth it to eliminate the chroot AUR build
# + the first-boot mkinitcpio retry pattern those failures used to require.
#
# NOTE: the -dkms kernel-module packages are NOT standalone AUR repos — each
# is a split package of its sibling -utils base (AUR PackageBase
# nvidia-{580,470,390}xx-utils). `git clone nvidia-470xx-dkms.git` returns an
# empty repo, so they must NOT be listed here (doing so just logs a "Could not
# obtain PKGBUILD … build failed" warning and ships no driver). They are
# emitted automatically when the -utils base builds and collected by the
# copy-every-sibling logic in the build loop below; install-gpu-drivers then
# pacman -U's nvidia-*-dkms by name out of /usr/local/share/pkgs/.
NVIDIA_DEPS=(
    "nvidia-580xx-utils"
    "lib32-nvidia-580xx-utils"
    "nvidia-580xx-settings"
    "nvidia-470xx-utils"
    "lib32-nvidia-470xx-utils"
    "nvidia-390xx-utils"
)

# Append (not branch) so the build loop below, which iterates AUR_DEPS, builds them.
if [[ "$NVIDIA_PROFILE" == true ]]; then
    AUR_DEPS+=("${NVIDIA_DEPS[@]}")
fi

# ── Preflight checks ───────────────────────────────────────────────────────
info "Running package-build preflight checks..."

if [[ ! -d "$PROFILE_DIR/airootfs" ]]; then
    die "airootfs/ not found at $PROFILE_DIR."
fi

if ! ping -c1 -W5 github.com &>/dev/null; then
    die "No network connectivity. Cannot clone dotfiles repository."
fi
info "Network OK."

for tool in git makepkg pacman yay; do
    if ! command -v "$tool" &>/dev/null; then
        die "Required tool '$tool' not found. Please install it first."
    fi
done

# ── Install host build dependencies for AUR packages ────────────────────────
# These are required to build certain AUR packages (e.g. otf-space-grotesk)
# and must be present on the host before the AUR build loop runs.
info "Installing host build dependencies for AUR packages..."
pacman -S --noconfirm --needed fontforge python-html2text 2>&1 | grep -v "is up to date" || true

# html2markdown is AUR-only — build user must install it via yay
if ! pacman -Qi html2markdown &>/dev/null; then
    info "Installing html2markdown (AUR) as build user..."
    # Ensure build user exists early enough to run yay here
    if ! id "$BUILD_USER" &>/dev/null; then
        useradd -m -G wheel "$BUILD_USER" 2>/dev/null || true
        echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$BUILD_USER"
        chmod 440 /etc/sudoers.d/"$BUILD_USER"
    fi
    su "$BUILD_USER" -c "yay -S --noconfirm --needed html2markdown" 2>&1 || \
        warn "html2markdown install failed — otf-space-grotesk build may fall back to cache."
else
    info "html2markdown already installed."
fi

# ── Setup ───────────────────────────────────────────────────────────────────
info "Setting up package-build environment..."

mkdir -p "$PKG_OUTPUT_DIR"
chmod -R 775 "$PKG_OUTPUT_DIR"
info "Package output directory: $PKG_OUTPUT_DIR"

# Fix the build-time pacman.conf to point to the actual output directory
BUILD_PACMAN_CONF="$PROFILE_DIR/pacman.conf"
if [[ -f "$BUILD_PACMAN_CONF" ]]; then
    sed -i "s|^Server = file:///.*pkgs$|Server = file://$PKG_OUTPUT_DIR|" "$BUILD_PACMAN_CONF"
    info "Updated build pacman.conf repo path to: file://$PKG_OUTPUT_DIR"
fi

# Apply clean build if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    info "Clean build — removing all existing pre-built packages..."
    rm -f "$PKG_OUTPUT_DIR"/*.pkg.tar.zst
    info "Package output directory cleared."

    # Also wipe the ISO output and mkarchiso work dirs so a --clean run
    # starts from a true clean slate. Without this, leftover work/ state
    # from a previous (possibly failed) run can interfere with the next
    # mkarchiso pacstrap, and stale ISOs in out/ accumulate. Bakes in
    # the manual `rm -rf out work` step that previously had to happen
    # between --clean iterations.
    if [[ -d "$OUT_DIR" ]]; then
        info "Removing $OUT_DIR ..."
        rm -rf "$OUT_DIR"
    fi
    if [[ -d "$WORK_DIR" ]]; then
        info "Removing $WORK_DIR ..."
        rm -rf "$WORK_DIR"
    fi
fi

# Apply calamares-only clean if requested
if [[ "$CLEAN_CALAMARES" == true ]]; then
    info "Removing calamares-mainstream packages from output dir..."
    rm -f "$PKG_OUTPUT_DIR"/calamares-mainstream-*.pkg.tar.zst
    info "calamares-mainstream cleared."
fi

# Create temporary build user if it doesn't exist
if ! id "$BUILD_USER" &>/dev/null; then
    info "Creating temporary build user: $BUILD_USER"
    useradd -m -G wheel "$BUILD_USER" || die "Failed to create build user $BUILD_USER"
else
    info "Build user $BUILD_USER already exists, reusing."
fi

chown "$BUILD_USER":"$BUILD_USER" "$PKG_OUTPUT_DIR"
chmod 775 "$PKG_OUTPUT_DIR"

echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$BUILD_USER"
chmod 440 /etc/sudoers.d/"$BUILD_USER"

# Create pacman wrapper (makepkg PACMAN var must be a real binary path)
PACMAN_WRAPPER="/usr/local/bin/pacman-noconfirm"
cat > "$PACMAN_WRAPPER" << 'WRAPPER'
#!/usr/bin/env bash
exec pacman --noconfirm "$@"
WRAPPER
chmod +x "$PACMAN_WRAPPER"

# ── Clone dotfiles ──────────────────────────────────────────────────────────
info "Cloning dotfiles repository (branch: $DOTFILES_BRANCH)..."
rm -rf "$PKG_WORK_DIR"
mkdir -p "$PKG_WORK_DIR"
chown -R "$BUILD_USER":"$BUILD_USER" "$PKG_WORK_DIR"

if ! su "$BUILD_USER" -c "git clone --depth=1 --recurse-submodules --shallow-submodules --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$PKG_WORK_DIR'"; then
    die "git clone failed. Check the branch name and repo URL."
fi

DIST_ARCH_PATH="$PKG_WORK_DIR/sdata/dist-arch"
if [[ ! -d "$DIST_ARCH_PATH" ]]; then
    die "Expected dist-arch directory missing at $DIST_ARCH_PATH"
fi

chown -R "$BUILD_USER":"$BUILD_USER" "$PKG_WORK_DIR"
info "Clone successful."

# ── Write per-package build script ──────────────────────────────────────────
TEMP_OUTPUT="/tmp/iso-pkg-output"
mkdir -p "$TEMP_OUTPUT"
chown "$BUILD_USER":"$BUILD_USER" "$TEMP_OUTPUT"

BUILD_SCRIPT="/tmp/build-pkg-iso.sh"
cat > "$BUILD_SCRIPT" << 'BUILDSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
PKGPATH="$1"
TEMP_OUT="$2"
cd "$PKGPATH"

DEPS=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${depends[@]:-} ${makedepends[@]:-}"' 2>/dev/null || true)
if [[ -n "$DEPS" ]]; then
    yay -S --noconfirm --needed --asdeps $DEPS 2>&1 || true
fi

PACMAN=/usr/local/bin/pacman-noconfirm PKGDEST="$TEMP_OUT" \
    makepkg --noconfirm --needed --nodeps 2>&1
BUILDSCRIPT
chmod 755 "$BUILD_SCRIPT"
chown "$BUILD_USER":"$BUILD_USER" "$BUILD_SCRIPT"

# ── Build meta-packages ────────────────────────────────────────────────────
SUCCESS_COUNT=0
FAILED_PKGS=()
TOTAL=${#METAPKGS[@]}

info "Building $TOTAL meta-packages..."
echo ""

for pkgname in "${METAPKGS[@]}"; do
    pkgpath="$DIST_ARCH_PATH/$pkgname"

    if [[ ! -d "$pkgpath" ]]; then
        warn "$pkgname — directory missing at $pkgpath, skipping."
        FAILED_PKGS+=("$pkgname (missing dir)")
        continue
    fi

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-[0-9]*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        pkg_ver=$(bash -c "cd '$pkgpath' && source PKGBUILD 2>/dev/null && echo \${pkgver}-\${pkgrel}" 2>/dev/null || true)
        if echo "$existing" | grep -q "$pkg_ver"; then
            info "$pkgname — already built at current version, skipping."
            ((SUCCESS_COUNT++)) || true
            continue
        fi
        info "$pkgname — newer version available, rebuilding..."
        rm -f "$PKG_OUTPUT_DIR/${pkgname}-"*.pkg.tar.zst
    fi

    info "Building $pkgname..."
    if su "$BUILD_USER" -c "bash '$BUILD_SCRIPT' '$pkgpath' '$TEMP_OUTPUT'"; then
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-[0-9]*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${pkgname}"*.pkg.tar.zst
            ((SUCCESS_COUNT++)) || true
            success "$pkgname built successfully."
        else
            warn "$pkgname — build ran but no .pkg.tar.zst found in temp output."
            warn "  Files in temp: $(ls $TEMP_OUTPUT 2>/dev/null || echo none)"
            FAILED_PKGS+=("$pkgname (no output file)")
        fi
    else
        warn "$pkgname — build failed."
        FAILED_PKGS+=("$pkgname")
    fi
    echo ""
done

# ── Build local PKGBUILDs ──────────────────────────────────────────────────
LOCAL_PKGBUILDS_DIR="$PROFILE_DIR/pkgbuilds"

build_local_pkg() {
    local pkgname="$1"
    local pkgdir="$LOCAL_PKGBUILDS_DIR/$pkgname"

    if [[ ! -d "$pkgdir" ]]; then
        warn "$pkgname — local PKGBUILD directory not found at $pkgdir, skipping."
        return
    fi

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-[0-9]*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        pkg_ver=$(bash -c "cd '$pkgdir' && source PKGBUILD 2>/dev/null && echo \${pkgver}-\${pkgrel}" 2>/dev/null || true)
        if echo "$existing" | grep -q "$pkg_ver"; then
            info "$pkgname — already built at current version, skipping."
            return
        fi
        info "$pkgname — newer version available, rebuilding..."
        rm -f "$PKG_OUTPUT_DIR/${pkgname}-"*.pkg.tar.zst
    fi

    local tmp_build_dir="/tmp/local-pkg-${pkgname}"
    rm -rf "$tmp_build_dir"
    cp -a "$pkgdir" "$tmp_build_dir"
    chown -R "$BUILD_USER":"$BUILD_USER" "$tmp_build_dir"

    info "Building local package: $pkgname..."
    if su "$BUILD_USER" -c "
        cd '$tmp_build_dir'
        PACMAN=/usr/local/bin/pacman-noconfirm \
        PKGDEST='$TEMP_OUTPUT' \
        makepkg -s --noconfirm --skippgpcheck 2>&1
    "; then
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-[0-9]*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${pkgname}"*.pkg.tar.zst
            rm -f /var/cache/pacman/pkg/${pkgname}-*.pkg.tar.zst 2>/dev/null || true
            success "$pkgname built successfully."
        else
            warn "$pkgname — build ran but no .pkg.tar.zst found in temp output."
        fi
    else
        warn "$pkgname — build failed."
    fi

    rm -rf "$tmp_build_dir"
    echo ""
}

info "Building local PKGBUILDs..."
build_local_pkg "calamares-mainstream"
# mpris-hyprland: per-tab MPRIS bridge for Firefox/Zen (lighter
# plasma-browser-integration replacement). Builds the Rust host + bundles the
# WebExtension .xpi and the browser auto-install policies. git-sourced PKGBUILD,
# so it tracks the published repo.
build_local_pkg "mpris-hyprland"

# Pull what the GitHub [mainstream] repo already provides so we don't rebuild
# (and drift from) those versions; the loop below skips anything it supplied.
download_mainstream_repo_pkgs "$PKG_OUTPUT_DIR"

# ── Build AUR dependency packages ──────────────────────────────────────────
info "Building ${#AUR_DEPS[@]} AUR dependency packages..."
echo ""

AUR_SCRIPT="/tmp/build-aur-dep.sh"
cat > "$AUR_SCRIPT" << 'AURSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
INPUT="$1"
TEMP_OUT="$2"
PKGNAME="${INPUT%%::*}"
SRCNAME="${INPUT##*::}"
WORK="/tmp/aur-dep-$SRCNAME"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

git clone --depth=1 "https://aur.archlinux.org/${SRCNAME}.git" . 2>&1

if [[ ! -f "PKGBUILD" ]]; then
    YAY_CACHE="$HOME/.cache/yay/$SRCNAME"
    yay -G "$SRCNAME" 2>/dev/null || true
    if [[ -d "$YAY_CACHE" ]] && [[ -f "$YAY_CACHE/PKGBUILD" ]]; then
        cp -a "$YAY_CACHE/." "$WORK/"
    fi
    cd "$WORK"
fi

if [[ ! -f "PKGBUILD" ]]; then
    echo "ERROR: Could not obtain PKGBUILD for $SRCNAME via git or yay"
    exit 1
fi

# Pre-install build + runtime deps via yay so AUR-only dependencies resolve.
# makepkg -s only queries pacman repos, and the build host has neither the
# AUR nor the local [mainstream] repo in /etc/pacman.conf — so a package
# whose dependency is itself an AUR package (e.g. nvidia-580xx-dkms depends
# on its nvidia-580xx-utils sibling) fails with "target not found". yay
# resolves AUR deps; we then build with --nodeps. Same pattern the
# meta-package build script uses above.
DEPS=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${depends[@]:-} ${makedepends[@]:-}"' 2>/dev/null || true)
if [[ -n "$DEPS" ]]; then
    yay -S --noconfirm --needed --asdeps $DEPS 2>&1 || true
fi

PACMAN=/usr/local/bin/pacman-noconfirm PKGDEST="$TEMP_OUT" \
    makepkg -f --noconfirm --needed --nodeps --skippgpcheck 2>&1
rm -rf "$WORK"
AURSCRIPT
chmod 755 "$AUR_SCRIPT"
chown "$BUILD_USER":"$BUILD_USER" "$AUR_SCRIPT"

# Required AUR deps that produced no package. Collected through the loop and
# checked after it so a transient AUR/source failure aborts here with a clear
# message instead of surfacing later as an opaque pacstrap "target not found".
MISSING_AUR=()

for entry in "${AUR_DEPS[@]}"; do
    pkgname="${entry%%::*}"

    if [[ -n "${GITHUB_PROVIDED[$pkgname]:-}" ]]; then
        info "$pkgname — using the [mainstream] GitHub build, skipping local rebuild."
        continue
    fi

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-[0-9]*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        info "$pkgname — already built, skipping."
        continue
    fi

    info "Building AUR dep: $pkgname..."
    # Clear the shared PKGDEST first so we collect *every* package this build
    # emits, not just the one named like the entry. AUR bases such as
    # nvidia-470xx-utils are split packages — a single makepkg run produces
    # nvidia-470xx-utils, nvidia-470xx-dkms and opencl-nvidia-470xx. The -dkms
    # kernel module has no separate AUR repo, so grabbing only the entry-named
    # artifact silently dropped it (the ISO shipped userspace with no driver).
    rm -f "$TEMP_OUTPUT"/*.pkg.tar.zst 2>/dev/null || true
    if su "$BUILD_USER" -c "bash '$AUR_SCRIPT' '$entry' '$TEMP_OUTPUT'"; then
        mapfile -t built < <(find "$TEMP_OUTPUT" -name "*.pkg.tar.zst" ! -name "*-debug-*")
        if [[ ${#built[@]} -gt 0 ]]; then
            cp "${built[@]}" "$PKG_OUTPUT_DIR/"
            success "$pkgname built successfully (${#built[@]} pkg(s): $(basename -a "${built[@]}" | tr '\n' ' '))."
        else
            warn "$pkgname — no output file found, skipping."
            MISSING_AUR+=("$pkgname")
        fi
    else
        warn "$pkgname — build failed, skipping."
        MISSING_AUR+=("$pkgname")
    fi
done

rm -f "$AUR_SCRIPT"
echo ""

if (( ${#MISSING_AUR[@]} > 0 )); then
    die "Required AUR package(s) produced no build output: ${MISSING_AUR[*]}. \
Each is listed in packages.x86_64, so pacstrap would fail later with an opaque \
\"target not found\". Re-run the build — transient AUR/source download failures \
usually clear on retry; if one persists, build it manually or add it to the \
[mainstream] GitHub repo's packages.list."
fi

# ── Build git-based packages ───────────────────────────────────────────────
info "Building git-based packages..."

GIT_PKGS_DIR="$PKG_WORK_DIR/git-pkgs"
mkdir -p "$GIT_PKGS_DIR"
chown "$BUILD_USER":"$BUILD_USER" "$GIT_PKGS_DIR"

GSF_PKG="mainstream-google-sans-flex"
existing_gsf=$(find "$PKG_OUTPUT_DIR" -name "${GSF_PKG}-*.pkg.tar.zst" 2>/dev/null | head -1)
if [[ -n "$existing_gsf" ]] && [[ "$CLEAN_BUILD" == false ]]; then
    info "$GSF_PKG — already built, skipping."
else
    info "Building $GSF_PKG..."
    GSF_BUILD="$GIT_PKGS_DIR/google-sans-flex"
    mkdir -p "$GSF_BUILD"
    chown "$BUILD_USER":"$BUILD_USER" "$GSF_BUILD"
    cat > "$GSF_BUILD/PKGBUILD" << 'GSFPKGBUILD'
pkgname=mainstream-google-sans-flex
pkgver=1.0
pkgrel=2
pkgdesc='Google Sans Flex variable font, packaged for Mainstream OS dotfiles'
arch=(any)
license=(OFL)
url="https://github.com/end-4/google-sans-flex"
provides=('illogical-impulse-google-sans-flex')
replaces=('illogical-impulse-google-sans-flex')
# The system-side install path keeps the illogical-impulse-google-sans-flex
# directory name so it lines up with the dotfiles' user-side font dir
# (XDG_DATA_HOME/fonts/illogical-impulse-google-sans-flex/) — easier mental
# model when debugging which font dir holds the live ISO copy.
source=("google-sans-flex::git+https://github.com/end-4/google-sans-flex.git")
sha256sums=('SKIP')

package() {
    install -dm755 "$pkgdir/usr/share/fonts/illogical-impulse-google-sans-flex"
    find "$srcdir/google-sans-flex" -name "*.ttf" -exec \
        install -m644 {} "$pkgdir/usr/share/fonts/illogical-impulse-google-sans-flex/" \;
    if [[ -f "$srcdir/google-sans-flex/LICENSE" ]]; then
        install -Dm644 "$srcdir/google-sans-flex/LICENSE" \
            "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    fi
}
GSFPKGBUILD
    chown "$BUILD_USER":"$BUILD_USER" "$GSF_BUILD/PKGBUILD"
    if su "$BUILD_USER" -c "cd '$GSF_BUILD' && PKGDEST='$TEMP_OUTPUT' makepkg -s --noconfirm --skippgpcheck 2>&1"; then
        built=$(find "$TEMP_OUTPUT" -name "${GSF_PKG}-*.pkg.tar.zst" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${GSF_PKG}"*.pkg.tar.zst
            success "$GSF_PKG built successfully."
        else
            warn "$GSF_PKG — build ran but no output file found."
        fi
    else
        warn "$GSF_PKG — build failed."
    fi
fi

# ── Build mainstream-microtex-git ─────────────────────────────────────────
# Built from the dotfiles repo's PKGBUILD so the rename (illogical-impulse-* →
# mainstream-*), pkgrel bumps, and provides/replaces metadata stay in sync.
# We don't use the METAPKGS loop because microtex needs makepkg -s (syncdeps)
# to pull cmake/tinyxml2/gtkmm3 etc. and --skippgpcheck on the git source.
MICROTEX_PKG="mainstream-microtex-git"
MICROTEX_SRC="$DIST_ARCH_PATH/$MICROTEX_PKG"
existing_microtex=$(find "$PKG_OUTPUT_DIR" -name "${MICROTEX_PKG}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
if [[ -n "$existing_microtex" ]] && [[ "$CLEAN_BUILD" == false ]]; then
    info "$MICROTEX_PKG — already built, skipping."
elif [[ ! -d "$MICROTEX_SRC" ]]; then
    warn "$MICROTEX_PKG — directory missing at $MICROTEX_SRC, skipping."
else
    info "Building $MICROTEX_PKG (compiles MicroTeX from source — this may take a few minutes)..."
    MICROTEX_BUILD="$GIT_PKGS_DIR/microtex"
    rm -rf "$MICROTEX_BUILD"
    cp -a "$MICROTEX_SRC" "$MICROTEX_BUILD"
    chown -R "$BUILD_USER":"$BUILD_USER" "$MICROTEX_BUILD"
    if su "$BUILD_USER" -c "
        cd '$MICROTEX_BUILD'
        PACMAN=/usr/local/bin/pacman-noconfirm \
        PKGDEST='$TEMP_OUTPUT' \
        makepkg -sf --noconfirm --skippgpcheck 2>&1
    "; then
        built=$(find "$TEMP_OUTPUT" -name "${MICROTEX_PKG}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${MICROTEX_PKG}"*.pkg.tar.zst
            success "$MICROTEX_PKG built successfully."
        else
            warn "$MICROTEX_PKG — build ran but no output file found."
        fi
    else
        warn "$MICROTEX_PKG — build failed."
    fi
fi

# ── Sanitize local repo (remove corrupt packages before indexing) ──────────
sanitize_local_repo "$PKG_OUTPUT_DIR"

# ── Generate local pacman repo database ────────────────────────────────────
info "Generating local pacman repo database..."
# Drop any leftover illogical-impulse.* db files from earlier ISO builds so
# pacman doesn't see two repos pointing at the same dir.
rm -f "$PKG_OUTPUT_DIR"/illogical-impulse.db{,.tar.gz,.tar.gz.old} \
      "$PKG_OUTPUT_DIR"/illogical-impulse.files{,.tar.gz,.tar.gz.old}
add_mainstream_db "$PKG_OUTPUT_DIR"
info "Repo database generated at $PKG_OUTPUT_DIR/mainstream.db.tar.gz (GPU driver packages excluded — files-only for install-gpu-drivers)."

# ── Purge stale copies from host pacman cache ──────────────────────────────
# mkarchiso's pacstrap (PHASE 2 below) uses the host's
# /var/cache/pacman/pkg/ as its package cache. When a previous ISO
# build deposited copies there and we just rebuilt the local repo
# with new checksums (e.g. after --clean), pacstrap finds the stale
# cached file, sees its checksum mismatch the freshly-regenerated
# mainstream.db, and aborts with "invalid or corrupted package".
# Without this purge, the only fix is `sudo pacman -Scc` between
# every --clean run — punishing for an iterative build loop.
#
# We only remove files whose names match what's now in our local
# repo, so unrelated cached packages (kernel, base-devel, etc.) stay
# warm. Per-package `rm` calls already exist inside the local
# PKGBUILD loop (line ~486), but those don't cover METAPKGS, AUR_DEPS,
# or the cmake-built mainstream-microtex-git / mainstream-google-sans-flex —
# this batch sweep covers everything in $PKG_OUTPUT_DIR uniformly.
info "Purging stale copies of locally-built packages from host pacman cache..."
_purged=0
for _pkg in "$PKG_OUTPUT_DIR"/*.pkg.tar.zst; do
    [[ -f "$_pkg" ]] || continue
    _cached="/var/cache/pacman/pkg/$(basename "$_pkg")"
    if [[ -f "$_cached" ]]; then
        rm -f "$_cached"
        (( _purged++ )) || true
    fi
done
info "Purged ${_purged} stale package(s) from /var/cache/pacman/pkg/."

# ── Deploy dotfiles to /etc/skel ───────────────────────────────────────────
SKEL_DIR="$PROFILE_DIR/airootfs/etc/skel"
DOTS_WORK="/tmp/iso-dots-deploy"

info "Deploying dotfiles to $SKEL_DIR..."

# Wipe any pre-existing skel venv when --clean or --refresh is active so that
# uv venv cannot silently reuse a stale venv from a previous build run.
# Without this, --refresh alone leaves the old venv in place and uv skips
# recreating it, meaning the patched SKEL_USER paths from the last build are
# baked in and the materialyoucolor check may pass against a stale install.
_SKEL_VENV_PRE="$SKEL_DIR/.local/state/quickshell/.venv"
if [[ "$REFRESH_PKGS" == true && -d "$_SKEL_VENV_PRE" ]]; then
    rm -rf "$_SKEL_VENV_PRE"
fi

rm -rf "$DOTS_WORK"
mkdir -p "$DOTS_WORK"
chown "$BUILD_USER":"$BUILD_USER" "$DOTS_WORK"

if su "$BUILD_USER" -c "git clone --depth=1 --recurse-submodules --shallow-submodules --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$DOTS_WORK'"; then
    if [[ -d "$DOTS_WORK/dots" ]]; then
        mkdir -p "$SKEL_DIR"
        # Mirror dots into the skel WITH deletions, so files removed from the
        # dotfiles repo don't live on in the skel and every fresh install
        # (the old cp -a copy-over shipped deleted QML/scripts for weeks).
        # Excluded paths are skel content that does not come from dots/:
        #  - build-deposited artifacts added by later phases of this script
        #    (python venv, prebuilt hyprland plugins, uv sdata, init-qs.sh)
        #  - deliberate ISO-only extras (.bash_profile, gtk settings.ini
        #    defaults, first_run marker, auto-drive-mount icon)
        # rsync does not delete excluded destination paths, so these survive
        # builds without being re-created each time.
        rsync -a --delete \
            --exclude='/.bash_profile' \
            --exclude='/.config/gtk-3.0/settings.ini' \
            --exclude='/.config/gtk-4.0/settings.ini' \
            --exclude='/.config/hypr/scripts/' \
            --exclude='/.local/share/hyprland/plugins/' \
            --exclude='/.local/share/icons/hicolor/scalable/apps/auto-drive-mount.svg' \
            --exclude='/.local/share/quickshell/sdata/uv/' \
            --exclude='/.local/state/quickshell/.venv/' \
            --exclude='/.local/state/quickshell/user/first_run.txt' \
            "$DOTS_WORK/dots/" "$SKEL_DIR/"
        # Hyprland 0.55 Lua config: each former `exec-once = ...` entry becomes a
        # separate `hl.on("hyprland.start", function() hl.exec_cmd("...") end)`
        # subscription. Multiple hl.on calls for the same event are additive, so
        # appending is safe and idempotent (the grep guard prevents re-inserts).
        EXECS_LUA="$SKEL_DIR/.config/hypr/custom/execs.lua"
        if [[ -f "$EXECS_LUA" ]] && ! grep -q "calamares-autostart" "$EXECS_LUA"; then
            info "Adding calamares-autostart to skel execs.lua..."
            echo 'hl.on("hyprland.start", function() hl.exec_cmd("/usr/local/bin/calamares-autostart") end)' >> "$EXECS_LUA"
        fi

        if [[ -f "$EXECS_LUA" ]] && ! grep -q "live-setup" "$EXECS_LUA"; then
            info "Adding live-setup to skel execs.lua..."
            echo 'hl.on("hyprland.start", function() hl.exec_cmd("/usr/local/bin/live-setup") end)' >> "$EXECS_LUA"
        fi

        if [[ -f "$EXECS_LUA" ]] && ! grep -q "dotfiles-first-login" "$EXECS_LUA"; then
            info "Adding dotfiles-first-login to skel execs.lua..."
            # Shell-operators (&&, ||) live inside the exec_cmd string — Hyprland
            # spawns the command via /bin/sh -c, so they're interpreted by sh,
            # not by Lua. Embedded double quotes are escaped for the outer shell
            # (printf %q would also work but echo -e + backslash is the same shape
            # used elsewhere in this script).
            echo 'hl.on("hyprland.start", function() hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user start dotfiles-first-login.service || /usr/local/bin/dotfiles-first-login") end)' >> "$EXECS_LUA"
        fi

        SCRIPTS_DIR="$SKEL_DIR/.config/hypr/scripts"
        mkdir -p "$SCRIPTS_DIR"
        if [[ -f "$PROFILE_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" ]]; then
            cp "$PROFILE_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" "$SCRIPTS_DIR/"
            chmod 755 "$SCRIPTS_DIR/init-qs.sh"
            info "init-qs.sh deployed to skel."
        fi

        # Deploy Mainstream Plymouth theme into the live ISO airootfs so the
        # live boot splash matches the brand. plymouthd.conf already points at
        # Theme=mainstream; without this copy, plymouth would fall back to the
        # generic "text" theme.
        PLYMOUTH_SRC="$DOTS_WORK/sdata/plymouth/mainstream"
        PLYMOUTH_DST="$PROFILE_DIR/airootfs/usr/share/plymouth/themes/mainstream"
        if [[ -d "$PLYMOUTH_SRC" ]]; then
            mkdir -p "$(dirname "$PLYMOUTH_DST")"
            rm -rf "$PLYMOUTH_DST"
            cp -a "$PLYMOUTH_SRC" "$PLYMOUTH_DST"
            find "$PLYMOUTH_DST" -type d -exec chmod 755 {} +
            find "$PLYMOUTH_DST" -type f -exec chmod 644 {} +
            # cp -a preserves the iso-builder UID from the clone, which leaves
            # status_shutdown.png / mainstream.script (and the rest of the
            # theme dir) unowned by the invoking user — git can't stash or
            # discard them afterward. The end-of-build chown only covers
            # SKEL_DIR; this directory lives under usr/share, so hand it back
            # explicitly to SUDO_USER here.
            if [[ -n "${SUDO_USER:-}" ]]; then
                chown -R "$SUDO_USER":"$SUDO_USER" "$PLYMOUTH_DST"
            fi
            info "Mainstream Plymouth theme deployed to airootfs."
        else
            warn "Mainstream Plymouth theme missing from dotfiles repo — live splash will fall back."
        fi

        # Deploy plugin rebuild.sh hooks from dots-hyprland sdata/ into the
        # iso's airootfs. dots-hyprland/sdata/{plugin}/rebuild.sh is the
        # single source of truth for both install paths:
        #   - On the iso, pacman's PostTransaction hook
        #     (95-{plugin}-rebuild.hook) invokes /usr/local/lib/{plugin}/rebuild.sh
        #     during package install — that file is what we drop here.
        #   - On a user's machine, install-dotfiles copies the same
        #     sdata/{plugin}/rebuild.sh to /usr/local/lib/{plugin}/rebuild.sh.
        # Pulling from a single sdata/ tree at iso build time means there's no
        # second copy in this repo to keep in sync.
        for _plugin in hyprbars scrolloverview; do
            _rb_src="$DOTS_WORK/sdata/$_plugin/rebuild.sh"
            _rb_dst="$PROFILE_DIR/airootfs/usr/local/lib/$_plugin/rebuild.sh"
            if [[ -f "$_rb_src" ]]; then
                mkdir -p "$(dirname "$_rb_dst")"
                cp -f "$_rb_src" "$_rb_dst"
                # Set 755 in the source tree too; profiledef.sh's
                # file_permissions array re-applies it after mkarchiso stages
                # into work/airootfs/, but having it right here keeps the
                # source tree self-consistent.
                chmod 755 "$_rb_dst"
                if [[ -n "${SUDO_USER:-}" ]]; then
                    chown "$SUDO_USER":"$SUDO_USER" "$_rb_dst"
                fi
                info "$_plugin rebuild.sh deployed to airootfs from sdata/."
            else
                warn "$_plugin rebuild.sh missing in dotfiles sdata/ ($_rb_src) — iso will ship without it; pacman's $_plugin rebuild hook will fail."
            fi
        done
        unset _plugin _rb_src _rb_dst

        info "Dotfiles deployed to skel."
    else
        warn "dots/ directory not found in repo — skel dotfiles not deployed."
    fi
    # DOTS_WORK cleanup deferred to after venv step (needs requirements.txt)
else
    warn "Failed to clone dotfiles for skel — skipping."
fi

# ── Pre-bake Python venv into skel ─────────────────────────────────────────
VENV_SKEL_PATH="$SKEL_DIR/.local/state/quickshell/.venv"
REQUIREMENTS="$DOTS_WORK/sdata/uv/requirements.txt"
PACKAGES_X86="$PROFILE_DIR/packages.x86_64"



# ── Step A: Determine what Python version the ISO will ship ─────────────────
# Python is not listed directly in packages.x86_64 — it arrives as a dep of
# a meta-package (e.g. mainstream-python).  Detection is two-stage:
#   1. Find any package in packages.x86_64 whose deps include a bare "python"
#      or "python3" — checked via `pacman -Si <pkg> | grep ^Depends`.
#   2. Resolve that python package's version via pacman -Si python.
ISO_PYTHON_PKG=""
ISO_PYTHON_VER=""   # e.g. "3.13"

_pacman_conf="$PROFILE_DIR/pacman.conf"
[[ -f "$_pacman_conf" ]] || _pacman_conf="/etc/pacman.conf"

if [[ -f "$PACKAGES_X86" ]]; then
    # Stage 1a: direct match — bare "python" or "python3" in the package list
    ISO_PYTHON_PKG=$(grep -E '^python3?$' "$PACKAGES_X86" | head -1 || true)

    # Stage 1b: indirect match — scan deps of every listed package for "python"
    if [[ -z "$ISO_PYTHON_PKG" ]]; then
        while IFS= read -r _pkg; do
            [[ -z "$_pkg" || "$_pkg" =~ ^# ]] && continue
            _deps=$(pacman --config "$_pacman_conf" -Si "$_pkg" 2>/dev/null \
                | awk '/^Depends/{found=1} found{print; if(/^[A-Z]/ && !/^Depends/){exit}}' \
                | grep -oE '\bpython3?\b' | head -1 || true)
            if [[ -n "$_deps" ]]; then
                ISO_PYTHON_PKG="python"
                break
            fi
        done < "$PACKAGES_X86"
    fi

    # Stage 2: resolve the actual version of the python package
    if [[ -n "$ISO_PYTHON_PKG" ]]; then
        _iso_full_ver=$(pacman --config "$_pacman_conf" -Si "$ISO_PYTHON_PKG" 2>/dev/null \
            | awk '/^Version/{print $3; exit}')

        # Collapse to MAJOR.MINOR (e.g. "3.13.3-1" → "3.13")
        ISO_PYTHON_VER=$(echo "$_iso_full_ver" | grep -oE '^[0-9]+\.[0-9]+')
    fi
fi

# ── Step B: Determine the host Python version ───────────────────────────────
HOST_PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)

# ── Step C: Version gate ─────────────────────────────────────────────────────
# The venv is pinned to the Python the ISO actually ships ($ISO_PYTHON_VER) so
# its .python-version stamp matches the installed interpreter and post-install
# keeps it instead of discarding it on an ABI mismatch (which forced a cold venv
# rebuild on every first boot). requirements.txt is compiled for that same
# version, and uv can download/manage the interpreter if the build host differs.
_version_ok=false
if python3 -c 'import sys; assert (sys.version_info.major, sys.version_info.minor) >= (3,8)' \
        &>/dev/null 2>&1; then
    # uv can download/manage Python 3.12 itself if it's not on the host,
    # so as long as uv is available we consider the gate passed.
    _version_ok=true
    info "Version gate passed — venv will be pinned to Python ${ISO_PYTHON_VER:-$HOST_PYTHON_VER} (ISO ships $ISO_PYTHON_VER)."
else
    warn "python3 not found on build host — skipping venv pre-bake."
fi

# ── Main pre-bake (only if all gates pass) ──────────────────────────────────
# Temporarily disable errexit so uv failures are non-fatal and the retry
# logic below can actually run.  set -e is restored after this block.
if [[ "$_version_ok" == true ]] && command -v uv &>/dev/null && [[ -f "$REQUIREMENTS" ]]; then
    set +e
    info "Pre-building Python venv for skel (host Python: $HOST_PYTHON_VER)..."
    mkdir -p "$(dirname "$VENV_SKEL_PATH")"
    venv_log() { echo "[venv-bake] $*"; }
    venv_log "=== venv pre-bake start ==="
    venv_log "host python=$HOST_PYTHON_VER  ISO python=$ISO_PYTHON_VER  pin=${ISO_PYTHON_VER:-$HOST_PYTHON_VER}"
    venv_log "VENV_SKEL_PATH=$VENV_SKEL_PATH"
    venv_log "REQUIREMENTS=$REQUIREMENTS  uv=$(command -v uv 2>/dev/null)"

    # Step 1: Create the venv pinned to the Python the ISO ships ($ISO_PYTHON_VER)
    # so the .python-version stamp matches the installed interpreter (and
    # requirements.txt, compiled for the same version). uv downloads/manages the
    # interpreter if the build host runs a different one.
    # --clear ensures no interactive prompt if a previous venv exists.
    _VENV_PIN="${ISO_PYTHON_VER:-$HOST_PYTHON_VER}"
    _pin_args=()
    [[ -n "$_VENV_PIN" ]] && _pin_args=(-p "$_VENV_PIN")
    uv venv --prompt .venv --clear "${_pin_args[@]}" "$VENV_SKEL_PATH" 2>&1
    _uv_venv_exit=${PIPESTATUS[0]}
    venv_log "uv venv exit=$_uv_venv_exit"

    # Step 2: Install packages. bin/python still points at uv's managed cache
    # at this point — that's intentional, uv needs it to resolve correct wheels.
    # The symlink is replaced with the system python3 after install completes.
    (set -o pipefail; uv pip install --python "$VENV_SKEL_PATH/bin/python" -r "$REQUIREMENTS") 2>&1
    _uv_pip_exit=${PIPESTATUS[0]}
    venv_log "uv pip install exit=$_uv_pip_exit"

    # Step 2b: Query the venv Python version BEFORE replacing the symlink —
    # while bin/python still resolves to uv's managed binary, it correctly
    # reports the version the venv was actually built for.
    _VENV_PY_VER=$("$VENV_SKEL_PATH/bin/python" -c \
        'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' \
        2>/dev/null || echo "$HOST_PYTHON_VER")
    venv_log "baked venv python=$_VENV_PY_VER (expected ISO=$ISO_PYTHON_VER)"

    # Guard: a baked venv whose Python differs from the ISO's gets discarded by
    # post-install (ABI mismatch) and rebuilt cold on first boot. Fail at build
    # time instead of silently shipping that.
    if [[ -n "$ISO_PYTHON_VER" && "$_VENV_PY_VER" != "$ISO_PYTHON_VER" ]]; then
        die "Baked venv Python ($_VENV_PY_VER) != ISO Python ($ISO_PYTHON_VER); fix the venv pin before shipping."
    fi

    # Step 2c: Replace dangling uv-cache symlinks with symlinks to system python3.
    # Must happen AFTER pip install and version query — uv needs its own managed
    # binary during install, and the version query needs it too.  After this the
    # symlinks resolve on the installed system where uv's cache doesn't exist.
    _SYS_PY3=$(command -v python3 2>/dev/null || true)
    if [[ -n "$_SYS_PY3" ]]; then
        while IFS= read -r _pylink; do
            ln -sf "$_SYS_PY3" "$_pylink"
            info "Relinked: $(basename "$_pylink") → $_SYS_PY3"
        done < <(find "$VENV_SKEL_PATH/bin" -maxdepth 1 -type l \
            -name 'python*' 2>/dev/null)
        info "Replaced uv-cache python symlinks → $_SYS_PY3"
    else
        warn "Could not find system python3 — python symlinks in venv may be dangling on target."
    fi

    venv_log "materialyoucolor present: $(compgen -G "$VENV_SKEL_PATH/lib/python*/site-packages/materialyoucolor*" >/dev/null 2>&1 && echo yes || echo no)"
    # Step 4: Gate on success then patch all paths
    if [[ $_uv_venv_exit -eq 0 ]] && \
       [[ $_uv_pip_exit  -eq 0 ]] && \
       compgen -G "$VENV_SKEL_PATH/lib/python*/site-packages/materialyoucolor*" >/dev/null 2>&1; then

        # Patch venv paths from the build tree to the SKEL_USER placeholder.
        # uv console scripts use a /bin/sh trampoline with the Python path on
        # line 2, so patch the whole file rather than only the shebang.

        find "$VENV_SKEL_PATH/bin" -type f -exec \
            sed -i "s|${VENV_SKEL_PATH}|/home/SKEL_USER/.local/state/quickshell/.venv|g" {} + 2>/dev/null || true
        find "$VENV_SKEL_PATH/bin" -maxdepth 1 -type f -exec chmod 755 {} + 2>/dev/null || true

        # Spot-check: confirm placeholder was written into the wrapper scripts
        find "$VENV_SKEL_PATH/bin" -maxdepth 1 -type f ! -name "*.py" | sort | while read -r f; do
            _line1=$(head -1 "$f" 2>/dev/null || echo '<empty>')
            _line2=$(sed -n '2p' "$f" 2>/dev/null || echo '<empty>')
        done

        # ── Patch pyvenv.cfg ────────────────────────────────────────────────
        # uv writes several path-bearing lines that the original single-pass
        # sed missed entirely because they don't contain VENV_SKEL_PATH:
        #
        #   home         = /usr/bin              ← host Python bin dir (NOT the venv path)
        #   python       = /usr/bin/python3.x    ← absolute host binary
        #   python_path  = /usr/bin/python3.x    ← same
        #
        # These survived unpatched into the ISO and told the installed system's
        # Python to look for python3.X in /usr/bin with whatever ABI was on the
        # build host — causing import failures when the versions differed.
        #
        # Fix: four passes —
        #   Pass 1: replace any occurrence of the full VENV_SKEL_PATH (existing logic)
        #   Pass 2: rewrite `home =` to point at the placeholder venv bin/
        #   Pass 3: rewrite `python =` to the placeholder python binary
        #   Pass 4: rewrite `python_path =` to the placeholder python binary
        #
        # post-install's existing regex
        #   s|/[^"'[:space:]]*\.local/state/quickshell/\.venv|$VENV_PATH|g
        # then rewrites all four placeholder values to the real installed path.
        if [[ -f "$VENV_SKEL_PATH/pyvenv.cfg" ]]; then

            # Pass 1: venv path occurrences (original)
            sed -i "s|${VENV_SKEL_PATH}|/home/SKEL_USER/.local/state/quickshell/.venv|g" \
                "$VENV_SKEL_PATH/pyvenv.cfg"

            # Pass 2: home = <host-bin-dir>  →  home = <placeholder>/bin
            sed -i -E \
                's|^(home\s*=\s*).*|\1/home/SKEL_USER/.local/state/quickshell/.venv/bin|' \
                "$VENV_SKEL_PATH/pyvenv.cfg"

            # Pass 3: python = <host-binary>  →  python = <placeholder>/bin/python
            sed -i -E \
                's|^(python\s*=\s*).*|\1/home/SKEL_USER/.local/state/quickshell/.venv/bin/python|' \
                "$VENV_SKEL_PATH/pyvenv.cfg"

            # Pass 4: python_path = <host-binary>  →  python_path = <placeholder>/bin/python
            sed -i -E \
                's|^(python_path\s*=\s*).*|\1/home/SKEL_USER/.local/state/quickshell/.venv/bin/python|' \
                "$VENV_SKEL_PATH/pyvenv.cfg"

        fi

        # ── Write Python version stamp ───────────────────────────────────────
        # Queried from the venv binary in Step 2b above, before the symlink
        # was replaced — so it accurately reflects the version uv built for.
        printf '%s\n' "$_VENV_PY_VER" > "$VENV_SKEL_PATH/.python-version"
        info "Python version stamp written: $_VENV_PY_VER"

        info "Python venv pre-built into skel ($VENV_SKEL_PATH)."
    else
        warn "Pre-baked venv incomplete — post-install will rebuild it from scratch."
        rm -rf "$VENV_SKEL_PATH"
    fi

    SKEL_SDATA="$SKEL_DIR/.local/share/quickshell/sdata/uv"
    mkdir -p "$SKEL_SDATA"
    cp "$REQUIREMENTS" "$SKEL_SDATA/"
    info "requirements.txt deployed to skel."
    set -e
else
    [[ "$_version_ok" == true ]] || warn "  reason: Python version gate failed (see above)"
    command -v uv &>/dev/null    || warn "  reason: uv not in PATH"
    [[ -f "$REQUIREMENTS" ]]     || warn "  reason: requirements.txt not found at $REQUIREMENTS"
    warn "Venv pre-bake skipped — post-install will build it on first run."

    # Still deploy requirements.txt so post-install's scratch build can find it
    if [[ -f "$REQUIREMENTS" ]]; then
        SKEL_SDATA="$SKEL_DIR/.local/share/quickshell/sdata/uv"
        mkdir -p "$SKEL_SDATA"
        cp "$REQUIREMENTS" "$SKEL_SDATA/"
        info "requirements.txt deployed to skel."
    fi
fi


# ── Pre-build Hyprland plugins ─────────────────────────────────────────────
# Build user-side Hyprland plugins from source on the build host and drop
# the resulting .so files into /etc/skel/.local/share/hyprland/plugins/ so
# fresh user accounts have a starter copy on first login.
#
# IMPORTANT: this is a *starter*, not the final artifact. Hyprland's plugin
# ABI is pinned to the exact compositor version, and Arch can publish new
# hyprland releases between this ISO build and the user's installation —
# meaning the prebuilt may not load. The dots post-install script
# (sdata/subcmd-install/3.files.sh:_ensure_hyprland_plugin) treats the
# prebuilt as a fallback only: it always rebuilds the plugin against the
# user's installed hyprland to guarantee ABI match, replacing the prebuilt
# with the freshly-built .so on success. The starter only matters when
# the rebuild itself fails (offline install, missing build deps), in which
# case the pacman rebuild hook will retry on the next `pacman -Syu` that
# touches hyprland.
#
# Build failures here are non-fatal — we warn and continue. The ISO still
# ships, and the post-install will build from source on the user's system.

info "Installing build deps for plugin prebuild..."
pacman -S --noconfirm --needed hyprland 2>&1 | grep -v "is up to date" || true

prebuild_hyprland_plugin() {
    local name="$1"
    local repo_url="$2"
    local branch="$3"
    local src_subdir="$4"
    local so_filename="$5"

    info "Pre-building $name plugin from $repo_url ($branch)..."

    local work="/tmp/iso-plugin-$name"
    rm -rf "$work"

    if ! su "$BUILD_USER" -c "git clone --depth=1 --branch '$branch' '$repo_url' '$work'"; then
        warn "$name: git clone failed — skipping prebuild (post-install will build from source)."
        return 0
    fi

    local build_dir="$work"
    if [[ -n "$src_subdir" ]]; then
        build_dir="$work/$src_subdir"
    fi

    if ! su "$BUILD_USER" -c "cd '$build_dir' && make all -j$(nproc)"; then
        warn "$name: make failed — skipping prebuild (post-install will build from source)."
        rm -rf "$work"
        return 0
    fi

    if [[ ! -f "$build_dir/$so_filename" ]]; then
        warn "$name: build succeeded but $so_filename not found at $build_dir — skipping prebuild."
        rm -rf "$work"
        return 0
    fi

    local skel_plugins="$SKEL_DIR/.local/share/hyprland/plugins"
    mkdir -p "$skel_plugins"
    cp -f "$build_dir/$so_filename" "$skel_plugins/$so_filename"
    chmod 755 "$skel_plugins/$so_filename"
    success "$so_filename pre-built and deployed to skel ($skel_plugins/$so_filename)."

    rm -rf "$work"
}

prebuild_hyprland_plugin "scrolloverview" \
    "https://github.com/MainstreamOS/hyprland-scroll-overview" \
    "mainstream" \
    "" \
    "scrolloverview.so"

prebuild_hyprland_plugin "hyprbars" \
    "https://github.com/hyprwm/hyprland-plugins" \
    "v0.55.0" \
    "hyprbars" \
    "hyprbars.so"


# Hand skel ownership back to the invoking user so Git can modify it later
# (also catches any prebuilt .so files dropped above).
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "$SKEL_DIR"
fi

rm -rf "$DOTS_WORK"

# ── Package-build cleanup ──────────────────────────────────────────────────
info "Cleaning up package-build environment..."
rm -rf "$PKG_WORK_DIR"
rm -rf "$TEMP_OUTPUT"
rm -f "$BUILD_SCRIPT"

userdel -r "$BUILD_USER" 2>/dev/null || true
rm -f /etc/sudoers.d/"$BUILD_USER"

# ── Package-build summary ──────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Package Build Summary: $SUCCESS_COUNT/$TOTAL packages successful"
echo " Output: $PKG_OUTPUT_DIR"
echo "============================================================"

if [[ ${#FAILED_PKGS[@]} -ne 0 ]]; then
    echo ""
    warn "The following packages failed:"
    for pkg in "${FAILED_PKGS[@]}"; do
        warn "  - $pkg"
    done
    echo ""
    warn "Fix the failures and re-run — successful packages will be skipped."
fi

echo ""
info "Listing built packages:"
ls -lh "$PKG_OUTPUT_DIR"/*.pkg.tar.zst 2>/dev/null || warn "No packages found in output directory."
echo ""

fi  # end REFRESH_PKGS

# #############################################################################
#
#   PHASE 2: ISO BUILD  (always runs)
#
# #############################################################################

info "═══════════════════════════════════════════════════════════════"
info "  PHASE 2: Building ISO"
info "═══════════════════════════════════════════════════════════════"

# ── Standard-edition slimming: drop legacy NVIDIA prebuilts ────────────────
# A prior --nvidia build leaves them in this persistent dir (bundled into the
# ISO), so a standard build prunes them. Files-only (not in the DB), so safe.
if [[ "$NVIDIA_PROFILE" != true ]]; then
    _PKG_DIR="$PROFILE_DIR/airootfs/usr/local/share/pkgs"
    _pruned=0
    for _glob in nvidia-580xx nvidia-470xx nvidia-390xx; do
        for _f in "$_PKG_DIR"/*"$_glob"*.pkg.tar.zst; do
            [[ -e "$_f" ]] || continue
            rm -f "$_f"
            (( _pruned++ )) || true
        done
    done
    (( _pruned > 0 )) && info "Standard edition: pruned ${_pruned} legacy NVIDIA prebuilt(s)." || true
    unset _PKG_DIR _pruned _glob _f
fi

# ── ISO build dependency check ─────────────────────────────────────────────
for _bin in mkfs.fat mmd mcopy xorriso mksquashfs curl tar make cc; do
    if ! command -v "${_bin}" &>/dev/null; then
        echo "ERROR: '${_bin}' not found. Install it on the build host." >&2
        exit 1
    fi
done

# ── Fetch latest upstream Limine ───────────────────────────────────────────
# Arch's [extra] repo can lag upstream Limine. Pull the latest binary release
# from limine-bootloader/limine on GitHub so each ISO ships current bootloader
# code (UEFI security fixes, new firmware compat, etc.). Refuse to build with a
# stale system Limine unless ALLOW_SYSTEM_LIMINE_FALLBACK=1 is set explicitly.
#
# After this step:
#   $LIMINE_DIR/{limine, limine-bios-cd.bin, limine-bios.sys, BOOTX64.EFI, ...}
# are the binaries used by mkarchiso (via bootmodes/limine.sh) and by the
# `limine bios-install` step that embeds the MBR bootstrap.
LIMINE_STAGE="$(mktemp -d /tmp/limine-upstream-XXXXXX)"
LIMINE_DIR="/usr/share/limine"   # fallback default
LIMINE_VERSION=""
ALLOW_SYSTEM_LIMINE_FALLBACK="${ALLOW_SYSTEM_LIMINE_FALLBACK:-0}"
_LIMINE_FETCH_OK=0

info "Fetching latest Limine release from GitHub..."
if _LATEST_TAG="$(curl -fsSL --retry 3 \
        https://api.github.com/repos/limine-bootloader/limine/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)" \
   && [[ -n "${_LATEST_TAG}" ]]; then

    _ASSET_URL="https://github.com/limine-bootloader/limine/releases/download/${_LATEST_TAG}/limine-binary.tar.xz"
    info "Downloading Limine ${_LATEST_TAG} binary tarball..."
    if curl -fsSL --retry 3 -o "${LIMINE_STAGE}/limine.tar.xz" "${_ASSET_URL}"; then
        if tar -xf "${LIMINE_STAGE}/limine.tar.xz" -C "${LIMINE_STAGE}"; then
            # Tarball extracts to limine-binary/
            _UPSTREAM_DIR="$(find "${LIMINE_STAGE}" -mindepth 1 -maxdepth 2 -type d \( -name 'limine-binary' -o -name 'limine-binary-*' \) | head -1)"
            if [[ -n "${_UPSTREAM_DIR}" \
                  && -f "${_UPSTREAM_DIR}/limine-bios-cd.bin" \
                  && -f "${_UPSTREAM_DIR}/limine-bios.sys" \
                  && -f "${_UPSTREAM_DIR}/BOOTX64.EFI" ]]; then
                if [[ ! -x "${_UPSTREAM_DIR}/limine" ]]; then
                    info "Building upstream Limine installer tool..."
                    make -C "${_UPSTREAM_DIR}" limine >/dev/null
                fi
                if [[ -x "${_UPSTREAM_DIR}/limine" ]]; then
                    LIMINE_DIR="${_UPSTREAM_DIR}"
                    LIMINE_VERSION="${_LATEST_TAG#v}"
                    if grep -aom1 "Limine ${LIMINE_VERSION}" "${LIMINE_DIR}/BOOTX64.EFI" >/dev/null; then
                        _LIMINE_FETCH_OK=1
                        info "Using upstream Limine ${LIMINE_VERSION} from ${LIMINE_DIR}"
                    else
                        warn "Upstream BOOTX64.EFI does not report Limine ${LIMINE_VERSION} — refusing to use it."
                    fi
                else
                    warn "Failed to build upstream Limine installer tool."
                fi
            else
                warn "Upstream Limine tarball missing expected files."
            fi
        else
            warn "Failed to extract upstream Limine tarball."
        fi
    else
        warn "Failed to download upstream Limine."
    fi
else
    warn "Failed to query GitHub for latest Limine release."
fi

if (( _LIMINE_FETCH_OK == 0 )); then
    if [[ "${ALLOW_SYSTEM_LIMINE_FALLBACK}" == "1" ]]; then
        warn "Using system Limine from ${LIMINE_DIR}; this may not be the latest upstream release."
    else
        die "Could not fetch/build latest upstream Limine. Refusing to build an ISO with stale bootloader binaries. Set ALLOW_SYSTEM_LIMINE_FALLBACK=1 to override."
    fi
fi
export LIMINE_DIR

# Validate whichever source we ended up with.
for _f in "${LIMINE_DIR}/limine-bios-cd.bin" \
          "${LIMINE_DIR}/limine-bios.sys" \
          "${LIMINE_DIR}/BOOTX64.EFI"; do
    if [[ ! -f "${_f}" ]]; then
        echo "ERROR: ${_f} not found. Install 'limine' on the build host or check network connectivity." >&2
        exit 1
    fi
done

# `limine bios-install` needs an executable. Use the upstream-provided one if
# we've got it, otherwise fall back to whatever's on $PATH.
if [[ -x "${LIMINE_DIR}/limine" ]]; then
    LIMINE_BIN="${LIMINE_DIR}/limine"
elif command -v limine &>/dev/null; then
    LIMINE_BIN="$(command -v limine)"
else
    echo "ERROR: no usable 'limine' binary found." >&2
    exit 1
fi

if [[ -n "${LIMINE_VERSION}" ]]; then
    "${LIMINE_BIN}" --version | head -1 | grep -F "Limine ${LIMINE_VERSION}" >/dev/null \
        || die "Limine installer tool version does not match ${LIMINE_VERSION}."
fi

trap 'restore_profile_overlay; rm -rf -- "${LIMINE_STAGE}"; rm -f -- "${PATCHED_MKARCHISO:-}"' EXIT

# ── Work directory ─────────────────────────────────────────────────────────
if (( CLEAR_WORK )) && [[ -d "${WORK_DIR}" ]]; then
    echo ">>> Clearing work directory: ${WORK_DIR}"
    rm -rf -- "${WORK_DIR}"
fi

mkdir -p -- "${OUT_DIR}" "${WORK_DIR}"

# mkarchiso caches bootmode function execution with work/base._make_bootmode_*.
# Always invalidate only the Limine boot artifacts so a reused work directory
# cannot carry old BOOTX64.EFI/BIOS binaries into a new ISO.
info "Invalidating cached Limine boot artifacts in work directory..."
rm -f -- \
    "${WORK_DIR}/base._make_bootmode_bios.limine" \
    "${WORK_DIR}/base._make_bootmode_uefi.limine" \
    "${WORK_DIR}/efiboot.img" \
    "${WORK_DIR}/iso/limine-bios-cd.bin" \
    "${WORK_DIR}/iso/limine-bios.sys" \
    "${WORK_DIR}/iso/EFI/BOOT/BOOTX64.EFI"

# ── Patch mkarchiso with Limine bootmode functions ─────────────────────────
PATCHED_MKARCHISO="$(mktemp /tmp/mkarchiso-limine-XXXXXX)"
chmod +x -- "${PATCHED_MKARCHISO}"

{
    head -1 "${MKARCHISO}"
    cat -- "${LIMINE_BOOTMODES}"
    tail -n +2 "${MKARCHISO}"
} > "${PATCHED_MKARCHISO}"

echo ">>> Building ISO (this takes several minutes)..."

# Sanitize the local repo one final time in case packages were corrupted
# outside of a --refresh run (e.g. interrupted previous build, bad download).
_LOCAL_REPO="${PROFILE_DIR}/airootfs/usr/local/share/pkgs"
if [[ -d "$_LOCAL_REPO" ]]; then
    sanitize_local_repo "$_LOCAL_REPO"
    # Rebuild the DB here (not just PHASE 1) so an ISO-only build whose edition
    # differs from the last --refresh still matches: post-prune for standard,
    # 580xx-included for --nvidia.
    add_mainstream_db "$_LOCAL_REPO"
fi

# no-op unless --nvidia; the EXIT trap restores the profile on any exit.
apply_profile_overlay

"${PATCHED_MKARCHISO}" \
    ${VERBOSE} \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"

if [[ -n "${LIMINE_VERSION}" ]]; then
    grep -aom1 "Limine ${LIMINE_VERSION}" "${WORK_DIR}/iso/EFI/BOOT/BOOTX64.EFI" >/dev/null \
        || die "Built ISO tree does not contain Limine ${LIMINE_VERSION} BOOTX64.EFI."
    grep -aom1 "Limine ${LIMINE_VERSION}" "${WORK_DIR}/iso/limine-bios.sys" >/dev/null \
        || die "Built ISO tree does not contain Limine ${LIMINE_VERSION} BIOS support binary."
    success "Verified ISO Limine boot binaries are ${LIMINE_VERSION}."
fi

# ── Find the output ISO ───────────────────────────────────────────────────
ISO_PATH="$(ls -t "${OUT_DIR}"/*.iso 2>/dev/null | head -1)"
if [[ -z "${ISO_PATH}" ]]; then
    echo "ERROR: No ISO found in ${OUT_DIR} after build." >&2
    exit 1
fi
echo ">>> ISO created: ${ISO_PATH}"

# ── Embed Limine BIOS bootstrap for USB hybrid boot ───────────────────────
echo ">>> Embedding Limine BIOS bootstrap (limine bios-install)..."
"${LIMINE_BIN}" bios-install "${ISO_PATH}"

# ── Strip the architecture suffix from the filename ───────────────────────
# mkarchiso composes the output as ${iso_name}-${iso_version}-${arch}.iso and
# offers no setting to suppress the -${arch} segment. Rename in place after
# bios-install so the embed step still operates on the mkarchiso-named file
# (avoids any chance of touching the wrong artefact mid-build).
_ARCH_SUFFIX="-$(awk -F= '/^arch=/{gsub(/"/,"",$2); print $2}' "${PROFILE_DIR}/profiledef.sh")"
if [[ -n "${_ARCH_SUFFIX}" && "${_ARCH_SUFFIX}" != "-" ]]; then
    _NEW_ISO_PATH="${ISO_PATH/${_ARCH_SUFFIX}.iso/.iso}"
    if [[ "${_NEW_ISO_PATH}" != "${ISO_PATH}" ]]; then
        mv -f -- "${ISO_PATH}" "${_NEW_ISO_PATH}"
        ISO_PATH="${_NEW_ISO_PATH}"
        echo ">>> Renamed ISO to: ${ISO_PATH}"
    fi
fi

echo ""
echo "Build complete."
echo "Output: ${ISO_PATH}"
echo ""
echo "Write to USB:  dd if='${ISO_PATH}' of=/dev/sdX bs=4M status=progress"
