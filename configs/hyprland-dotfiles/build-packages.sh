#!/usr/bin/env bash
# =============================================================================
# build-packages.sh
# Pre-builds all illogical-impulse meta-packages and deposits them into
# airootfs/usr/local/share/pkgs/ ready to be baked into the ISO squashfs.
#
# Usage (from archiso root directory):
#   ./build-packages.sh
#
# Re-run any time you want to update packages before rebuilding the ISO.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# HELPERS — defined before flag parsing so they are available immediately
# ---------------------------------------------------------------------------
log()     { echo "[build-packages] $*"; }
info()    { log "INFO:  $*"; }
warn()    { log "WARN:  $*"; }
die()     { log "FATAL: $*"; exit 1; }
success() { log "OK:    $*"; }

# ---------------------------------------------------------------------------
# FLAGS
# ---------------------------------------------------------------------------
CLEAN_BUILD=false

for arg in "$@"; do
    case "$arg" in
        --clean|-c)
            CLEAN_BUILD=true
            info "Clean build requested — all existing packages will be removed and rebuilt."
            ;;
        --help|-h)
            echo "Usage: sudo ./build-packages.sh [--clean|-c]"
            echo ""
            echo "  --clean, -c    Remove all existing pre-built packages and rebuild from scratch"
            echo "  --help,  -h    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Run with --help for usage."
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/airootfs/usr/local/share/pkgs"
DOTFILES_REPO="https://github.com/gregorytrentmartinjr/dots-hyprland.git"
DOTFILES_BRANCH="newcustom"
WORK_DIR="/tmp/iso-pkg-build"
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

# AUR runtime dependencies of the meta-packages that aren't in official repos
# These must also be pre-built and included in the local repo so mkarchiso
# can resolve them during the ISO build.
# Note: matugen, songrec, go-yq, ksshaskpass are in official repos — not listed here.
# Note: matugen, songrec, go-yq, ksshaskpass are in official [extra] — not listed here.
AUR_DEPS=(
    "calamares::calamares"  # AUR-only, git repo requires auth — uses yay cache fallback
    "ttf-google-sans"
    "limine-mkinitcpio-hook"
    "limine-snapper-sync"
    "topgrade"
    "wlogout"
    "adw-gtk-theme-git"
    "breeze-plus"
    "darkly-bin"
    # Note: these three use different yay source package names than their output package names
    # otf-space-grotesk is a split package from 38c3-styles
    # ttf-material-symbols-variable-git is a split package from material-symbols-git
    # qt6-avif-image-plugin is a split package from qt5-avif-image-plugin
    "otf-space-grotesk::38c3-styles"
    "ttf-material-symbols-variable-git::material-symbols-git"
    "ttf-readex-pro-variable"
    "ttf-readex-pro"
    "ttf-rubik-vf"
    "ttf-twemoji"
    "google-breakpad"
    "qt6-avif-image-plugin::qt5-avif-image-plugin"
)


# ---------------------------------------------------------------------------
# PREFLIGHT CHECKS
# ---------------------------------------------------------------------------
info "Running preflight checks..."

# Must run as root so we can create users and install deps
if [[ "$EUID" -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
fi

# Must be run from the archiso root directory
if [[ ! -d "$SCRIPT_DIR/airootfs" ]]; then
    die "airootfs/ not found. Run this script from your archiso root directory."
fi

# Network check
if ! ping -c1 -W5 github.com &>/dev/null; then
    die "No network connectivity. Cannot clone dotfiles repository."
fi
info "Network OK."

# Ensure required tools are present
for tool in git makepkg pacman yay; do
    if ! command -v "$tool" &>/dev/null; then
        die "Required tool '$tool' not found. Please install it first."
    fi
done

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------
info "Setting up build environment..."

# Create full output directory path as root first
# (iso-builder cannot create parent directories under /home/...)
mkdir -p "$OUTPUT_DIR"
chmod -R 775 "$OUTPUT_DIR"
info "Output directory: $OUTPUT_DIR"

# Apply clean build if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    info "Clean build — removing all existing pre-built packages..."
    rm -f "$OUTPUT_DIR"/*.pkg.tar.zst
    info "Output directory cleared."
fi

# Create temporary build user if it doesn't exist
# (makepkg refuses to run as root)
if ! id "$BUILD_USER" &>/dev/null; then
    info "Creating temporary build user: $BUILD_USER"
    useradd -m -G wheel "$BUILD_USER" || die "Failed to create build user $BUILD_USER"
else
    info "Build user $BUILD_USER already exists, reusing."
fi

# Now that the user exists, set ownership and permissions on output directory
chown "$BUILD_USER":"$BUILD_USER" "$OUTPUT_DIR"
chmod 775 "$OUTPUT_DIR"

# Ensure passwordless sudo for build user
echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$BUILD_USER"
chmod 440 /etc/sudoers.d/"$BUILD_USER"

# Create pacman wrapper (makepkg PACMAN var must be a real binary path)
PACMAN_WRAPPER="/usr/local/bin/pacman-noconfirm"
cat > "$PACMAN_WRAPPER" << 'WRAPPER'
#!/usr/bin/env bash
exec pacman --noconfirm "$@"
WRAPPER
chmod +x "$PACMAN_WRAPPER"

# ---------------------------------------------------------------------------
# CLONE DOTFILES
# ---------------------------------------------------------------------------
info "Cloning dotfiles repository (branch: $DOTFILES_BRANCH)..."

# Clean up any previous run
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
chown -R "$BUILD_USER":"$BUILD_USER" "$WORK_DIR"

if ! su "$BUILD_USER" -c "git clone --depth=1 --recurse-submodules --shallow-submodules --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$WORK_DIR'"; then
    die "git clone failed. Check the branch name and repo URL."
fi

DIST_ARCH_PATH="$WORK_DIR/sdata/dist-arch"
if [[ ! -d "$DIST_ARCH_PATH" ]]; then
    die "Expected dist-arch directory missing at $DIST_ARCH_PATH"
fi

# Ensure build user owns the entire tree
chown -R "$BUILD_USER":"$BUILD_USER" "$WORK_DIR"
info "Clone successful."

# ---------------------------------------------------------------------------
# WRITE PER-PACKAGE BUILD SCRIPT
# ---------------------------------------------------------------------------
# iso-builder builds into a temp dir it owns to avoid permission issues
# with parent directories under airootfs/ — root copies results afterward
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

# Install all deps via yay (handles AUR deps like topgrade, go-yq, ksshaskpass)
DEPS=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${depends[@]:-} ${makedepends[@]:-}"' 2>/dev/null || true)
if [[ -n "$DEPS" ]]; then
    yay -S --noconfirm --needed --asdeps $DEPS 2>&1 || true
fi

# Build into temp dir that iso-builder owns — avoids parent dir permission issues
PACMAN=/usr/local/bin/pacman-noconfirm PKGDEST="$TEMP_OUT" \
    makepkg --noconfirm --needed --nodeps 2>&1
BUILDSCRIPT
chmod 755 "$BUILD_SCRIPT"
chown "$BUILD_USER":"$BUILD_USER" "$BUILD_SCRIPT"

# ---------------------------------------------------------------------------
# BUILD LOOP
# ---------------------------------------------------------------------------
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

    # Check if a fresh build already exists in output dir
    # (allows re-runs to skip unchanged packages unless --clean was passed)
    existing=$(find "$OUTPUT_DIR" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        # Get version from PKGBUILD
        pkg_ver=$(bash -c "cd '$pkgpath' && source PKGBUILD 2>/dev/null && echo \${pkgver}-\${pkgrel}" 2>/dev/null || true)
        if echo "$existing" | grep -q "$pkg_ver"; then
            info "$pkgname — already built at current version, skipping."
            ((SUCCESS_COUNT++)) || true
            continue
        fi
        info "$pkgname — newer version available, rebuilding..."
        rm -f "$OUTPUT_DIR/${pkgname}-"*.pkg.tar.zst
    fi

    info "Building $pkgname..."
    if su "$BUILD_USER" -c "bash '$BUILD_SCRIPT' '$pkgpath' '$TEMP_OUTPUT'"; then
        # Verify the package file was actually produced
        # Copy built package from temp dir to OUTPUT_DIR as root
        # Exclude -debug packages — we only want the main package file
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$OUTPUT_DIR/"
            # Also copy debug package if present (optional, won't break anything)
            debug_pkg=$(find "$TEMP_OUTPUT" -name "${pkgname}-debug-*.pkg.tar.zst" | head -1)
            [[ -n "$debug_pkg" ]] && cp "$debug_pkg" "$OUTPUT_DIR/" || true
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

# ---------------------------------------------------------------------------
# BUILD AUR DEPENDENCY PACKAGES
# ---------------------------------------------------------------------------
info "Building ${#AUR_DEPS[@]} AUR dependency packages..."
echo ""

# Write a simple AUR build script
AUR_SCRIPT="/tmp/build-aur-dep.sh"
cat > "$AUR_SCRIPT" << 'AURSCRIPT'
#!/usr/bin/env bash
set -uo pipefail
# Support "outputpkg::sourcepkg" format for split packages with different source names
INPUT="$1"
TEMP_OUT="$2"
PKGNAME="${INPUT%%::*}"   # output package name (what we want to find in TEMP_OUT)
SRCNAME="${INPUT##*::}"   # source package name (what to clone/build from AUR)
WORK="/tmp/aur-dep-$SRCNAME"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

# Try git clone first using the SOURCE package name
git clone --depth=1 "https://aur.archlinux.org/${SRCNAME}.git" . 2>&1

# If clone produced empty repo, fall back to yay cache
# yay stores PKGBUILDs in ~/.cache/yay/<sourcepkg>/
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
    # Support "outputpkg::sourcepkg" format for split packages
    pkgname="${entry%%::*}"   # output package name used to find the .pkg.tar.zst

    # Skip if already built
    existing=$(find "$OUTPUT_DIR" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" 2>/dev/null | head -1)
    if [[ -n "$existing" ]] && [[ "$CLEAN_BUILD" == false ]]; then
        info "$pkgname — already built, skipping."
        continue
    fi

    info "Building AUR dep: $pkgname..."
    if su "$BUILD_USER" -c "bash '$AUR_SCRIPT' '$entry' '$TEMP_OUTPUT'"; then
        built=$(find "$TEMP_OUTPUT" -name "${pkgname}-*.pkg.tar.zst" ! -name "*-debug-*" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$OUTPUT_DIR/"
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

# ---------------------------------------------------------------------------
# BUILD GIT-BASED PACKAGES (not on AUR, cloned directly from GitHub)
# ---------------------------------------------------------------------------
info "Building git-based packages..."

GIT_PKGS_DIR="$WORK_DIR/git-pkgs"
mkdir -p "$GIT_PKGS_DIR"
chown "$BUILD_USER":"$BUILD_USER" "$GIT_PKGS_DIR"

# illogical-impulse-google-sans-flex
GSF_PKG="illogical-impulse-google-sans-flex"
existing_gsf=$(find "$OUTPUT_DIR" -name "${GSF_PKG}-*.pkg.tar.zst" 2>/dev/null | head -1)
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
    find "$srcdir/google-sans-flex" -name "*.ttf" -exec         install -m644 {} "$pkgdir/usr/share/fonts/illogical-impulse-google-sans-flex/" \;
    if [[ -f "$srcdir/google-sans-flex/LICENSE" ]]; then
        install -Dm644 "$srcdir/google-sans-flex/LICENSE"             "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    fi
}
GSFPKGBUILD
    chown "$BUILD_USER":"$BUILD_USER" "$GSF_BUILD/PKGBUILD"
    if su "$BUILD_USER" -c "cd '$GSF_BUILD' && PKGDEST='$TEMP_OUTPUT' makepkg -s --noconfirm --skippgpcheck 2>&1"; then
        built=$(find "$TEMP_OUTPUT" -name "${GSF_PKG}-*.pkg.tar.zst" | head -1)
        if [[ -n "$built" ]]; then
            cp "$built" "$OUTPUT_DIR/"
            rm -f "$TEMP_OUTPUT/${GSF_PKG}"*.pkg.tar.zst
            success "$GSF_PKG built successfully."
        else
            warn "$GSF_PKG — build ran but no output file found."
        fi
    else
        warn "$GSF_PKG — build failed."
    fi
fi

# ---------------------------------------------------------------------------
# GENERATE LOCAL PACMAN REPO DATABASE
# ---------------------------------------------------------------------------
info "Generating local pacman repo database..."
# repo-add creates the .db file pacman uses to find packages in the local repo
repo-add "$OUTPUT_DIR/illogical-impulse.db.tar.gz" "$OUTPUT_DIR"/*.pkg.tar.zst
info "Repo database generated at $OUTPUT_DIR/illogical-impulse.db.tar.gz"

# ---------------------------------------------------------------------------
# DEPLOY DOTFILES TO /etc/skel
# ---------------------------------------------------------------------------
# Files in /etc/skel are copied to every new user's home on creation,
# including liveuser. This is the correct place for live ISO dotfiles.
SKEL_DIR="$SCRIPT_DIR/airootfs/etc/skel"
info "Deploying dotfiles to $SKEL_DIR..."

DOTS_WORK="/tmp/iso-dots-deploy"
rm -rf "$DOTS_WORK"
mkdir -p "$DOTS_WORK"
chown "$BUILD_USER":"$BUILD_USER" "$DOTS_WORK"

if su "$BUILD_USER" -c "git clone --depth=1 --recurse-submodules --shallow-submodules --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$DOTS_WORK'"; then
    if [[ -d "$DOTS_WORK/dots" ]]; then
        mkdir -p "$SKEL_DIR"
        cp -a "$DOTS_WORK/dots/." "$SKEL_DIR/"
        # Add calamares autostart — uses a guard script that checks for live ISO
        # environment so it is safe to leave in execs.conf on installed systems
        EXECS_CONF="$SKEL_DIR/.config/hypr/custom/execs.conf"
        if [[ -f "$EXECS_CONF" ]] && ! grep -q "calamares-autostart" "$EXECS_CONF"; then
            info "Adding calamares-autostart to skel execs.conf..."
            echo "exec-once = /usr/local/bin/calamares-autostart" >> "$EXECS_CONF"
        fi

        # Add live-setup for wallpaper/color generation on live ISO first boot
        if [[ -f "$EXECS_CONF" ]] && ! grep -q "live-setup" "$EXECS_CONF"; then
            info "Adding live-setup to skel execs.conf..."
            echo "exec-once = /usr/local/bin/live-setup" >> "$EXECS_CONF"
        fi

        # Add dotfiles-first-login as exec-once so Hyprland triggers it directly
        # This ensures WAYLAND_DISPLAY is set — profile.d alone is not reliable
        if [[ -f "$EXECS_CONF" ]] && ! grep -q "dotfiles-first-login" "$EXECS_CONF"; then
            info "Adding dotfiles-first-login to skel execs.conf..."
            echo "exec-once = bash /etc/profile.d/dotfiles-first-login.sh" >> "$EXECS_CONF"
        fi

        # Deploy init-qs.sh to skel scripts directory
        SCRIPTS_DIR="$SKEL_DIR/.config/hypr/scripts"
        mkdir -p "$SCRIPTS_DIR"
        if [[ -f "$SCRIPT_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" ]]; then
            cp "$SCRIPT_DIR/../airootfs/etc/skel/.config/hypr/scripts/init-qs.sh" "$SCRIPTS_DIR/"
            chmod 755 "$SCRIPTS_DIR/init-qs.sh"
            info "init-qs.sh deployed to skel."
        fi

        info "Dotfiles deployed to skel."
    else
        warn "dots/ directory not found in repo — skel dotfiles not deployed."
    fi
    rm -rf "$DOTS_WORK"
else
    warn "Failed to clone dotfiles for skel — skipping."
fi

# ---------------------------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------------------------
info "Cleaning up build environment..."
rm -rf "$WORK_DIR"
rm -rf "$TEMP_OUTPUT"
rm -f "$BUILD_SCRIPT"

# Remove temporary build user and sudoers entry
userdel -r "$BUILD_USER" 2>/dev/null || true
rm -f /etc/sudoers.d/"$BUILD_USER"

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Build Summary: $SUCCESS_COUNT/$TOTAL packages successful"
echo " Output: $OUTPUT_DIR"
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
ls -lh "$OUTPUT_DIR"/*.pkg.tar.zst 2>/dev/null || warn "No packages found in output directory."

echo ""
info "Done. Rebuild the ISO to include the updated packages."
