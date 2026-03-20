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

# =============================================================================
# HELPERS
# =============================================================================
log()     { echo "[build] $*"; }
info()    { log "INFO:  $*"; }
warn()    { log "WARN:  $*"; }
die()     { log "FATAL: $*"; exit 1; }
success() { log "OK:    $*"; }

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

Examples:
  sudo ./build.sh                     # ISO only (packages must already exist)
  sudo ./build.sh --refresh           # Rebuild packages + ISO
  sudo ./build.sh --clean -c          # Full clean rebuild (packages + work dir + ISO)
  sudo ./build.sh --cleancal          # Rebuild calamares + ISO
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

# #############################################################################
#
#   PHASE 1: PACKAGE BUILD  (only when --refresh / --clean / --cleancal)
#
# #############################################################################
if [[ "$REFRESH_PKGS" == true ]]; then

info "═══════════════════════════════════════════════════════════════"
info "  PHASE 1: Building packages"
info "═══════════════════════════════════════════════════════════════"

# ── Package-build config ────────────────────────────────────────────────────
PKG_OUTPUT_DIR="$PROFILE_DIR/airootfs/usr/local/share/pkgs"
DOTFILES_REPO="https://github.com/gregorytrentmartinjr/dots-hyprland.git"
DOTFILES_BRANCH="newcustom"
PKG_WORK_DIR="/tmp/iso-pkg-build"
BUILD_USER="iso-builder"

METAPKGS=(
    "illogical-impulse-audio"
    "illogical-impulse-backlight"
    "illogical-impulse-basic"
    "illogical-impulse-fonts-themes"
    "illogical-impulse-gnome"
    "illogical-impulse-hyprland"
    "illogical-impulse-kde"
    "illogical-impulse-portal"
    "illogical-impulse-python"
    "illogical-impulse-screencapture"
    "illogical-impulse-toolkit"
    "illogical-impulse-widgets"
    "illogical-impulse-microtex-git"
    "illogical-impulse-quickshell-git"
    "illogical-impulse-extras"
    "illogical-impulse-bibata-modern-classic-bin"
)

AUR_DEPS=(
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
    "ttf-readex-pro-variable"
    "ttf-readex-pro"
    "ttf-rubik-vf"
    "ttf-twemoji"
    "google-breakpad"
    "qt6-avif-image-plugin::qt5-avif-image-plugin"
)

# Prebuilt packages to download instead of building from source.
# Format: "filename URL"
# These are Qt5 packages removed from official repos as part of the Qt5→Qt6 transition.
PREBUILT_PKGS=(
    "qt5-webengine-5.15.19-4-x86_64.pkg.tar.zst https://sourceforge.net/projects/fabiololix-os-archive/files/Packages/qt5-webengine-5.15.19-4-x86_64.pkg.tar.zst/download"
    "qt5-webchannel-5.15.18+kde+r3-1-x86_64.pkg.tar.zst https://sourceforge.net/projects/fabiololix-os-archive/files/Packages/qt5-webchannel-5.15.18%2Bkde%2Br3-1-x86_64.pkg.tar.zst/download"
    "qt5-location-5.15.18+kde+r7-2-x86_64.pkg.tar.zst https://archive.archlinux.org/packages/q/qt5-location/qt5-location-5.15.18%2Bkde%2Br7-2-x86_64.pkg.tar.zst"
    "qt5-tools-5.15.18+kde+r3-1-x86_64.pkg.tar.zst https://archive.archlinux.org/packages/q/qt5-tools/qt5-tools-5.15.18%2Bkde%2Br3-1-x86_64.pkg.tar.zst"
)

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

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
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
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            debug_pkg=$(find "$TEMP_OUTPUT" -name "${pkgname}-debug-*.pkg.tar.zst" | head -1)
            [[ -n "$debug_pkg" ]] && cp "$debug_pkg" "$PKG_OUTPUT_DIR/" || true
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

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
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
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
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

PACMAN=/usr/local/bin/pacman-noconfirm PKGDEST="$TEMP_OUT" \
    makepkg -s --noconfirm --needed --skippgpcheck 2>&1
rm -rf "$WORK"
AURSCRIPT
chmod 755 "$AUR_SCRIPT"
chown "$BUILD_USER":"$BUILD_USER" "$AUR_SCRIPT"

for entry in "${AUR_DEPS[@]}"; do
    pkgname="${entry%%::*}"

    existing=$(find "$PKG_OUTPUT_DIR" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        info "$pkgname — already built, skipping."
        continue
    fi

    info "Building AUR dep: $pkgname..."
    if su "$BUILD_USER" -c "bash '$AUR_SCRIPT' '$entry' '$TEMP_OUTPUT'"; then
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$PKG_OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${pkgname}"*.pkg.tar.zst
            success "$pkgname built successfully."
        else
            warn "$pkgname — no output file found, skipping."
        fi
    else
        warn "$pkgname — build failed, skipping."
    fi
done

rm -f "$AUR_SCRIPT"
echo ""

# ── Build git-based packages ───────────────────────────────────────────────
info "Building git-based packages..."

GIT_PKGS_DIR="$PKG_WORK_DIR/git-pkgs"
mkdir -p "$GIT_PKGS_DIR"
chown "$BUILD_USER":"$BUILD_USER" "$GIT_PKGS_DIR"

GSF_PKG="illogical-impulse-google-sans-flex"
existing_gsf=$(find "$PKG_OUTPUT_DIR" -name "${GSF_PKG}-*.pkg.tar.zst" 2>/dev/null | head -1)
if [[ -n "$existing_gsf" ]] && [[ "$CLEAN_BUILD" == false ]]; then
    info "$GSF_PKG — already built, skipping."
else
    info "Building $GSF_PKG..."
    GSF_BUILD="$GIT_PKGS_DIR/google-sans-flex"
    mkdir -p "$GSF_BUILD"
    chown "$BUILD_USER":"$BUILD_USER" "$GSF_BUILD"
    cat > "$GSF_BUILD/PKGBUILD" << 'GSFPKGBUILD'
pkgname=illogical-impulse-google-sans-flex
pkgver=1.0
pkgrel=1
pkgdesc='Google Sans Flex variable font as used by end-4/dots-hyprland'
arch=(any)
license=(OFL)
url="https://github.com/end-4/google-sans-flex"
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

# ── Download prebuilt packages ─────────────────────────────────────────────
if [[ ${#PREBUILT_PKGS[@]} -gt 0 ]]; then
    info "Downloading ${#PREBUILT_PKGS[@]} prebuilt packages..."
    for entry in "${PREBUILT_PKGS[@]}"; do
        pkg_file="${entry%% *}"
        pkg_url="${entry#* }"

        if [[ -f "$PKG_OUTPUT_DIR/$pkg_file" ]] && [[ "$CLEAN_BUILD" == false ]]; then
            info "$pkg_file — already present, skipping download."
            continue
        fi

        info "Downloading $pkg_file..."
        if curl -L --retry 4 --retry-delay 2 -o "$PKG_OUTPUT_DIR/$pkg_file" "$pkg_url"; then
            success "$pkg_file downloaded successfully."
        else
            warn "$pkg_file — download failed."
        fi
    done
    echo ""
fi

# ── Generate local pacman repo database ────────────────────────────────────
info "Generating local pacman repo database..."
repo-add "$PKG_OUTPUT_DIR/illogical-impulse.db.tar.gz" "$PKG_OUTPUT_DIR"/*.pkg.tar.zst
info "Repo database generated at $PKG_OUTPUT_DIR/illogical-impulse.db.tar.gz"

# ── Deploy dotfiles to /etc/skel ───────────────────────────────────────────
SKEL_DIR="$PROFILE_DIR/airootfs/etc/skel"
info "Deploying dotfiles to $SKEL_DIR..."

DOTS_WORK="/tmp/iso-dots-deploy"
rm -rf "$DOTS_WORK"
mkdir -p "$DOTS_WORK"
chown "$BUILD_USER":"$BUILD_USER" "$DOTS_WORK"

if su "$BUILD_USER" -c "git clone --depth=1 --recurse-submodules --shallow-submodules --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$DOTS_WORK'"; then
    if [[ -d "$DOTS_WORK/dots" ]]; then
        mkdir -p "$SKEL_DIR"
        cp -a "$DOTS_WORK/dots/." "$SKEL_DIR/"
        EXECS_CONF="$SKEL_DIR/.config/hypr/custom/execs.conf"
        if [[ -f "$EXECS_CONF" ]] && ! grep -q "calamares-autostart" "$EXECS_CONF"; then
            info "Adding calamares-autostart to skel execs.conf..."
            echo "exec-once = /usr/local/bin/calamares-autostart" >> "$EXECS_CONF"
        fi

        if [[ -f "$EXECS_CONF" ]] && ! grep -q "live-setup" "$EXECS_CONF"; then
            info "Adding live-setup to skel execs.conf..."
            echo "exec-once = /usr/local/bin/live-setup" >> "$EXECS_CONF"
        fi

        if [[ -f "$EXECS_CONF" ]] && ! grep -q "dotfiles-first-login" "$EXECS_CONF"; then
            info "Adding dotfiles-first-login to skel execs.conf..."
            echo "exec-once = bash /etc/profile.d/dotfiles-first-login.sh" >> "$EXECS_CONF"
        fi

        SCRIPTS_DIR="$SKEL_DIR/.config/hypr/scripts"
        mkdir -p "$SCRIPTS_DIR"
        if [[ -f "$PROFILE_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" ]]; then
            cp "$PROFILE_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" "$SCRIPTS_DIR/"
            chmod 755 "$SCRIPTS_DIR/init-qs.sh"
            info "init-qs.sh deployed to skel."
        fi

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

if command -v uv &>/dev/null && [[ -f "$REQUIREMENTS" ]]; then
    info "Pre-building Python venv for skel..."
    mkdir -p "$(dirname "$VENV_SKEL_PATH")"

    if uv venv "$VENV_SKEL_PATH" 2>&1 && \
       uv pip install --python "$VENV_SKEL_PATH/bin/python" -r "$REQUIREMENTS" 2>&1; then
        find "$VENV_SKEL_PATH/bin" -type f -exec \
            sed -i "1s|^#!${VENV_SKEL_PATH}|#!/home/SKEL_USER/.local/state/quickshell/.venv|" {} + 2>/dev/null || true
        info "Python venv pre-built into skel ($VENV_SKEL_PATH)."
    else
        warn "Failed to pre-build Python venv — will be created on first login instead."
        rm -rf "$VENV_SKEL_PATH"
    fi

    SKEL_SDATA="$SKEL_DIR/.local/share/quickshell/sdata/uv"
    mkdir -p "$SKEL_SDATA"
    cp "$REQUIREMENTS" "$SKEL_SDATA/"
    info "requirements.txt deployed to skel."
else
    warn "uv or requirements.txt not found — Python venv will be created on first login."
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

# ── ISO build dependency check ─────────────────────────────────────────────
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

# ── Work directory ─────────────────────────────────────────────────────────
if (( CLEAR_WORK )) && [[ -d "${WORK_DIR}" ]]; then
    echo ">>> Clearing work directory: ${WORK_DIR}"
    rm -rf -- "${WORK_DIR}"
fi

mkdir -p -- "${OUT_DIR}" "${WORK_DIR}"

# ── Patch mkarchiso with Limine bootmode functions ─────────────────────────
PATCHED_MKARCHISO="$(mktemp /tmp/mkarchiso-limine-XXXXXX)"
trap 'rm -f -- "${PATCHED_MKARCHISO}"' EXIT
chmod +x -- "${PATCHED_MKARCHISO}"

{
    head -1 "${MKARCHISO}"
    cat -- "${LIMINE_BOOTMODES}"
    tail -n +2 "${MKARCHISO}"
} > "${PATCHED_MKARCHISO}"

echo ">>> Building ISO (this takes several minutes)..."
"${PATCHED_MKARCHISO}" \
    ${VERBOSE} \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"

# ── Find the output ISO ───────────────────────────────────────────────────
ISO_PATH="$(ls -t "${OUT_DIR}"/*.iso 2>/dev/null | head -1)"
if [[ -z "${ISO_PATH}" ]]; then
    echo "ERROR: No ISO found in ${OUT_DIR} after build." >&2
    exit 1
fi
echo ">>> ISO created: ${ISO_PATH}"

# ── Embed Limine BIOS bootstrap for USB hybrid boot ───────────────────────
echo ">>> Embedding Limine BIOS bootstrap (limine bios-install)..."
limine bios-install "${ISO_PATH}"

echo ""
echo "Build complete."
echo "Output: ${ISO_PATH}"
echo ""
echo "Write to USB:  dd if='${ISO_PATH}' of=/dev/sdX bs=4M status=progress"
