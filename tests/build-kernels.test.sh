#!/usr/bin/env bash
# Which kernels each edition's image and package store carry, from build.sh's
# seed scan and its checks on the finished image, run against fakes.
set -uo pipefail
ARCHISO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ARCHISO_ROOT/build.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0; N=0
chk() { N=$((N+1)); [[ "$2" == "$3" ]] || { echo "  FAIL [$1] got '$2' want '$3'"; FAILS=$((FAILS+1)); }; }

# lift the pieces out of build.sh, without running the build
eval "$(grep -E '^(WELCOME_PKGS|HARDWARE_PKGS|INSTALL_STEP_PKGS|LEGACY_NVIDIA_PKGS|ONLINE_ONLY_PKGS)=\(' "$BUILD")"
for f in legacy_edition_keeps mainstream_unneeded_pkgs image_pkg_version verify_image_kernel verify_store_kernels; do
    eval "$(awk "/^$f\\(\\) \\{/,/^\\}/" "$BUILD")"
done

# ---- 1. the [mainstream] packages the image's store leaves out
# A db where both kernels' headers provide linux-headers, which a seeded DKMS
# package depends on; the performance pair sorts last, so it answers for the name.
mkpkg() {  # name version base [depends] [provides]
    local d="$TMP/db/$1-$2"
    mkdir -p "$d"
    {
        printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%BASE%%\n%s\n\n' "$1" "$2" "$3"
        [[ -n "${4:-}" ]] && printf '%%DEPENDS%%\n%s\n\n' "${4// /$'\n'}"
        [[ -n "${5:-}" ]] && printf '%%PROVIDES%%\n%s\n\n' "${5// /$'\n'}"
    } > "$d/desc"
}
mkpkg mainstream 7.3.6-1 mainstream
mkpkg mainstream-headers 7.3.6-1 mainstream "" "linux-headers=7.3.6"
mkpkg mainstream-performance 7.3.6-1 mainstream-performance
mkpkg mainstream-performance-headers 7.3.6-1 mainstream-performance "" "linux-headers=7.3.6"
mkpkg mainstream-tas2783-dkms 1.0-1 mainstream-tas2783-dkms "dkms linux-headers"
mkpkg proton-mainstream 10.0-1 proton-mainstream
mkpkg zen-browser-bin 1.0-1 zen-browser-bin
mkpkg unseeded-thing 1.0-1 unseeded-thing
mkpkg t2fanrd r21.01df44d-1 t2fanrd
mkpkg apple-t2-audio-config 0.4.r21.ga973d53-1 apple-t2-audio-config "alsa-ucm-conf"
# A GTX 900 to Titan V card's driver provides nvidia-utils, which packages.x86_64
# names, as [mainstream] publishes it.
mkpkg nvidia-580xx-utils 580.196.07-1 nvidia-580xx-utils "egl-wayland vulkan-swrast" "nvidia-utils nvidia-libgl"
mkpkg nvidia-580xx-dkms 580.196.07-1 nvidia-580xx-utils "dkms nvidia-580xx-utils=580.196.07" "NVIDIA-MODULE"
mkpkg opencl-nvidia-580xx 580.196.07-1 nvidia-580xx-utils "" "opencl-nvidia"
mkpkg lib32-nvidia-580xx-utils 580.196.07-1 lib32-nvidia-580xx-utils "lib32-vulkan-swrast" "lib32-nvidia-libgl lib32-nvidia-utils=580.196.07"
mkpkg nvidia-580xx-settings 580.196.07-1 nvidia-580xx-settings "nvidia-utils libxnvctrl-580xx" "nvidia-settings"
mkpkg libxnvctrl-580xx 580.196.07-1 nvidia-580xx-settings "" "libxnvctrl"
tar czf "$TMP/mainstream.db.tar.gz" -C "$TMP/db" .
METAPKGS=(); AUR_DEPS=(); LOCAL_BUILT_PKGS=()
PROFILE_DIR="$ARCHISO_ROOT/configs/hyprland-dotfiles"
PKG_OUTPUT_DIR="$TMP/out"; mkdir -p "$PKG_OUTPUT_DIR"
unneeded() { mainstream_unneeded_pkgs "$TMP/mainstream.db.tar.gz" | cut -d' ' -f1 | LC_ALL=C sort | tr '\n' ' '; }

sorted() { printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' '; }
LEGACY_NV="lib32-nvidia-580xx-utils libxnvctrl-580xx nvidia-580xx-dkms nvidia-580xx-settings nvidia-580xx-utils opencl-nvidia-580xx"
# The T2 packages are in the live root's list, so the store keeps them too.
# shellcheck disable=SC2086
chk store-standard "$(unneeded)" \
    "$(sorted $LEGACY_NV mainstream-performance mainstream-performance-headers unseeded-thing zen-browser-bin)"
# The legacy edition names the driver's AUR bases; it builds and stages them itself.
AUR_DEPS=(nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings nvidia-470xx-utils lib32-nvidia-470xx-utils nvidia-390xx-utils)
# shellcheck disable=SC2086
chk store-legacy-edition "$(unneeded)" \
    "$(sorted $LEGACY_NV mainstream-performance mainstream-performance-headers unseeded-thing zen-browser-bin)"
AUR_DEPS=()
# Not downloaded on any edition, and only the legacy edition keeps the copies it
# built itself in the store.
NVIDIA_PROFILE=true
chk keeps-legacy-edition "$(legacy_edition_keeps nvidia-580xx-utils && legacy_edition_keeps libxnvctrl-580xx && echo yes || echo no)" "yes"
chk keeps-legacy-edition-only-its-own "$(legacy_edition_keeps zen-browser-bin && echo yes || echo no)" "no"
NVIDIA_PROFILE=false
chk keeps-standard "$(legacy_edition_keeps nvidia-580xx-utils && echo yes || echo no)" "no"
unset NVIDIA_PROFILE

# ---- 2. the finished image boots only its own kernel and leaves DKMS's key behind
WORK_DIR="$TMP/work"; RELEASE_VERSION=""
AIR="$WORK_DIR/x86_64/airootfs"; BOOTDIR="$WORK_DIR/iso/arch/boot/x86_64"
success() { echo "ok: $*"; }
warn() { echo "warn: $*"; }
die_rejecting_iso() { echo "REJECTED: $*"; exit 1; }
installed() {  # name version [provides]
    local d="$AIR/var/lib/pacman/local/$1-$2"
    mkdir -p "$d"
    printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n' "$1" "$2" > "$d/desc"
    [[ -n "${3:-}" ]] && printf '%%PROVIDES%%\n%s\n\n' "$3" >> "$d/desc"
    return 0
}
standard_image() {
    rm -rf "$WORK_DIR"
    installed mainstream 7.3.6-1
    installed mainstream-headers 7.3.6-1 linux-headers=7.3.6
    mkdir -p "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms" "$AIR/var/lib/dkms" "$BOOTDIR"
    echo mainstream > "$AIR/usr/lib/modules/7.3.6-1-mainstream/pkgbase"
    : > "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms/nvidia.ko.zst"
    echo 'kernel/drivers/staging/t2bce/t2bce_core.ko.zst:' > "$AIR/usr/lib/modules/7.3.6-1-mainstream/modules.dep"
    : > "$BOOTDIR/vmlinuz-mainstream"
    : > "$BOOTDIR/initramfs-mainstream.img"
}
verdict() { local out; out=$( ( "$@" ) 2>&1 ); [[ "$out" == *REJECTED:* ]] && echo rejected || echo passed; }

standard_image
chk image-clean "$(verdict verify_image_kernel)" "passed"
chk image-t2-verified "$( (verify_image_kernel) 2>&1 | grep -c 'carries the T2 drivers')" "1"
: > "$AIR/var/lib/dkms/mok.key"
chk image-mok-key "$(verdict verify_image_kernel)" "rejected"
chk image-mok-key-named "$( (verify_image_kernel) 2>&1 | grep -c '/var/lib/dkms/mok.key')" "1"
rm -f "$AIR/var/lib/dkms/mok.key"; : > "$AIR/var/lib/dkms/mok.pub"
chk image-mok-pub "$(verdict verify_image_kernel)" "rejected"
standard_image; installed linux 6.18.1.arch1-1
chk image-arch-kernel "$(verdict verify_image_kernel)" "rejected"
standard_image; rm -f "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms/nvidia.ko.zst"
chk image-no-nvidia "$(verdict verify_image_kernel)" "rejected"
standard_image; : > "$BOOTDIR/vmlinuz-mainstream-performance"
chk image-extra-boot-kernel "$(verdict verify_image_kernel)" "rejected"
# Headers that do not provide linux-headers are a warning on a test build.
standard_image; rm -rf "$AIR/var/lib/pacman/local/mainstream-headers-"*; installed mainstream-headers 7.3.6-1
chk image-headers-no-provide "$( (verify_image_kernel) 2>&1 | grep -c 'does not provide linux-headers')" "1"
# An image built from the packages under their old names boots no kernel by today's name.
standard_image; rm -rf "$AIR/var/lib/pacman/local/mainstream-"*; installed linux-mainstream 7.3.6-1
echo linux-mainstream > "$AIR/usr/lib/modules/7.3.6-1-mainstream/pkgbase"
chk image-old-name "$(verdict verify_image_kernel)" "rejected"

image_says() { ( verify_image_kernel ) 2>&1 | grep -oE '^(REJECTED|warn)' | head -1; }
standard_image; installed linux-t2 7.3.5-1; : > "$BOOTDIR/vmlinuz-linux-t2"
chk image-t2linux-kernel "$(verdict verify_image_kernel)" "rejected"
# A kernel without the T2 drivers is a warning on a test build and refused on a release.
standard_image; : > "$AIR/usr/lib/modules/7.3.6-1-mainstream/modules.dep"
chk image-no-t2bce "$(image_says)" "warn"
RELEASE_VERSION=4.2.0
chk image-no-t2bce-release "$(image_says)" "REJECTED"
RELEASE_VERSION=""

# ---- 3. the store holds no kernel the image does not boot; refused on a release
STORE="$AIR/usr/local/share/pkgs"
store_with() { rm -rf "$STORE"; mkdir -p "$STORE"; local f; for f in "$@"; do : > "$STORE/$f-7.3.6-1-x86_64.pkg.tar.zst"; done; }
store_verdict() { ( verify_store_kernels ) 2>&1 | grep -oE '^(REJECTED|warn|ok)' | head -1; }
RELEASE_VERSION=""
store_with mainstream-headers
chk store-standard-own "$(store_verdict)" "ok"
store_with mainstream-performance-headers
chk store-standard-perf "$(store_verdict)" "warn"
RELEASE_VERSION=4.2.0
chk store-standard-perf-release "$(store_verdict)" "REJECTED"
RELEASE_VERSION=""
store_with mainstream-headers t2fanrd apple-t2-audio-config
chk store-t2-packages "$(store_verdict)" "ok"
# By name: Mainstream's other packages are not kernels, and a store from before
# the rename can still hold the old kernel packages.
store_with mainstream mainstream-headers mainstream-system mainstream-performance-tools
chk store-other-packages "$(store_verdict)" "ok"
store_with mainstream-performance-eac
chk store-eac "$(store_verdict)" "warn"
store_with linux-mainstream-headers
chk store-old-name "$(store_verdict)" "warn"
store_with linux-mainstream-performance
chk store-old-perf "$(store_verdict)" "warn"

# ---- 4. the standard profile boots a T2 Mac, and the test firmware overlay goes back
SRC="$ARCHISO_ROOT/configs/hyprland-dotfiles"
T2_OPTS='intel_iommu=on iommu=pt pm_async=off modprobe.blacklist=hci_bcm4377'
chk profile-t2-packages "$(grep -cxE 't2fanrd|apple-t2-audio-config' "$SRC/packages.x86_64")" "2"
chk profile-t2-entry "$(grep -c "^options .* $T2_OPTS %KERNEL_PARAMS%\$" "$SRC/efiboot/loader/entries/02-archiso-x86_64-linux-t2.conf")" "1"
chk profile-t2-no-modules-load "$(grep -c 'modules_load=' "$SRC/efiboot/loader/entries/02-archiso-x86_64-linux-t2.conf")" "0"
chk profile-t2-entry-kernel "$(grep -c '^linux .*/vmlinuz-mainstream$' "$SRC/efiboot/loader/entries/02-archiso-x86_64-linux-t2.conf")" "1"
# Only that entry turns the IOMMU on; every other machine boots as before.
chk profile-t2-opts-once "$(grep -rl 'intel_iommu=on' "$SRC/efiboot" "$SRC/syslinux" "$SRC/profiledef.sh" | wc -l)" "1"

eval "$(awk "/^_MACBOOK_TEST_FIRMWARE_REPO='\$/,/^'\$/" "$BUILD")"
for f in _overlay_stash _overlay_creates apply_test_firmware_overlay apply_profile_overlay restore_profile_overlay; do
    eval "$(awk "/^$f\\(\\) \\{/,/^\\}/" "$BUILD")"
done
info() { :; }; die() { echo "DIED: $*"; exit 1; }
PROFILE_DIR="$TMP/profile"
fresh_profile() {
    rm -rf "$PROFILE_DIR" "$TMP/overlay-bak"
    mkdir -p "$PROFILE_DIR/airootfs/etc"
    cp "$SRC/packages.x86_64" "$SRC/profiledef.sh" "$SRC/pacman.conf" "$PROFILE_DIR/"
    cp "$SRC/airootfs/etc/pacman.conf" "$PROFILE_DIR/airootfs/etc/"
    _OVERLAY_BAK_PATH="$TMP/overlay-bak"; _OVERLAY_BAK_DIR=""
}
listed() { grep -qx "$1" "$PROFILE_DIR/packages.x86_64" && echo yes || echo no; }
unchanged() { cmp -s "$SRC/$1" "$PROFILE_DIR/$1" && echo yes || echo no; }
NVIDIA_PROFILE=false; MACBOOK_TEST_FIRMWARE=false
fresh_profile
apply_profile_overlay >/dev/null
chk standard-no-overlay "$(unchanged packages.x86_64) $(unchanged profiledef.sh) $(unchanged pacman.conf)" "yes yes yes"
# The test-firmware build reads Apple's firmware from arch-mact2 while it is built,
# and the installed system's pacman.conf still never names that repository.
MACBOOK_TEST_FIRMWARE=true
fresh_profile
apply_profile_overlay >/dev/null 2>&1
chk testfw-build-repo "$(grep -c '^\[arch-mact2\]$' "$PROFILE_DIR/pacman.conf")" "1"
chk testfw-installed-conf "$(unchanged airootfs/etc/pacman.conf)" "yes"
chk testfw-firmware "$(listed apple-bcm-firmware)" "yes"
chk testfw-keeps-standard "$(listed mainstream) $(listed nvidia-open-dkms) $(listed t2fanrd)" "yes yes yes"
chk testfw-name "$(grep -c '^iso_name="mainstreamos-desktop-linux-macbook-testfw"$' "$PROFILE_DIR/profiledef.sh")" "1"
chk testfw-params "$(diff <(grep -v '^iso_name=' "$SRC/profiledef.sh") <(grep -v '^iso_name=' "$PROFILE_DIR/profiledef.sh") >/dev/null && echo same || echo changed)" "same"
restore_profile_overlay
chk testfw-restored "$(unchanged packages.x86_64) $(unchanged profiledef.sh) $(unchanged pacman.conf)" "yes yes yes"
MACBOOK_TEST_FIRMWARE=false

[[ $FAILS -eq 0 ]] && echo "build-kernels: all $N assertions PASS" || echo "build-kernels: $FAILS of $N FAILED"
exit $FAILS
