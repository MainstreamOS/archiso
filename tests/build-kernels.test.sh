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
eval "$(grep -E '^(WELCOME_PKGS|HARDWARE_PKGS|INSTALL_STEP_PKGS|ONLINE_ONLY_PKGS)=\(' "$BUILD")"
for f in mainstream_unneeded_pkgs image_pkg_version verify_image_kernel verify_store_kernels; do
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
mkpkg linux-mainstream 7.3.6-1 linux-mainstream
mkpkg linux-mainstream-headers 7.3.6-1 linux-mainstream "" "linux-headers=7.3.6"
mkpkg linux-mainstream-performance 7.3.6-1 linux-mainstream-performance
mkpkg linux-mainstream-performance-headers 7.3.6-1 linux-mainstream-performance "" "linux-headers=7.3.6"
mkpkg mainstream-tas2783-dkms 1.0-1 mainstream-tas2783-dkms "dkms linux-headers"
mkpkg proton-mainstream 10.0-1 proton-mainstream
mkpkg zen-browser-bin 1.0-1 zen-browser-bin
mkpkg unseeded-thing 1.0-1 unseeded-thing
tar czf "$TMP/mainstream.db.tar.gz" -C "$TMP/db" .
METAPKGS=(); AUR_DEPS=(); LOCAL_BUILT_PKGS=()
PROFILE_DIR="$ARCHISO_ROOT/configs/hyprland-dotfiles"
PKG_OUTPUT_DIR="$TMP/out"; mkdir -p "$PKG_OUTPUT_DIR"
unneeded() { mainstream_unneeded_pkgs "$TMP/mainstream.db.tar.gz" | cut -d' ' -f1 | LC_ALL=C sort | tr '\n' ' '; }

MACBOOK_PROFILE=false
chk store-standard "$(unneeded)" \
    "linux-mainstream-performance linux-mainstream-performance-headers unseeded-thing zen-browser-bin "
MACBOOK_PROFILE=true
chk store-macbook "$(unneeded)" \
    "linux-mainstream linux-mainstream-headers linux-mainstream-performance linux-mainstream-performance-headers unseeded-thing zen-browser-bin "

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
    installed linux-mainstream 7.3.6-1
    installed linux-mainstream-headers 7.3.6-1 linux-headers=7.3.6
    mkdir -p "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms" "$AIR/var/lib/dkms" "$BOOTDIR"
    echo linux-mainstream > "$AIR/usr/lib/modules/7.3.6-1-mainstream/pkgbase"
    : > "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms/nvidia.ko.zst"
    : > "$BOOTDIR/vmlinuz-linux-mainstream"
    : > "$BOOTDIR/initramfs-linux-mainstream.img"
}
verdict() { local out; out=$( ( "$@" ) 2>&1 ); [[ "$out" == *REJECTED:* ]] && echo rejected || echo passed; }

MACBOOK_PROFILE=false
standard_image
chk image-clean "$(verdict verify_image_kernel)" "passed"
: > "$AIR/var/lib/dkms/mok.key"
chk image-mok-key "$(verdict verify_image_kernel)" "rejected"
chk image-mok-key-named "$( (verify_image_kernel) 2>&1 | grep -c '/var/lib/dkms/mok.key')" "1"
rm -f "$AIR/var/lib/dkms/mok.key"; : > "$AIR/var/lib/dkms/mok.pub"
chk image-mok-pub "$(verdict verify_image_kernel)" "rejected"
standard_image; installed linux 6.18.1.arch1-1
chk image-arch-kernel "$(verdict verify_image_kernel)" "rejected"
standard_image; rm -f "$AIR/usr/lib/modules/7.3.6-1-mainstream/updates/dkms/nvidia.ko.zst"
chk image-no-nvidia "$(verdict verify_image_kernel)" "rejected"
standard_image; : > "$BOOTDIR/vmlinuz-linux-mainstream-performance"
chk image-extra-boot-kernel "$(verdict verify_image_kernel)" "rejected"

MACBOOK_PROFILE=true
rm -rf "$WORK_DIR"; installed linux-t2 6.18.1-1
mkdir -p "$BOOTDIR"; : > "$BOOTDIR/vmlinuz-linux-t2"; : > "$BOOTDIR/initramfs-linux-t2.img"
chk image-macbook "$(verdict verify_image_kernel)" "passed"
installed linux-mainstream 7.3.6-1
chk image-macbook-mainstream "$(verdict verify_image_kernel)" "rejected"

# ---- 3. the store holds no kernel the image does not boot; refused on a release
STORE="$AIR/usr/local/share/pkgs"
store_with() { rm -rf "$STORE"; mkdir -p "$STORE"; local f; for f in "$@"; do : > "$STORE/$f-7.3.6-1-x86_64.pkg.tar.zst"; done; }
store_verdict() { ( verify_store_kernels ) 2>&1 | grep -oE '^(REJECTED|warn|ok)' | head -1; }
MACBOOK_PROFILE=false; RELEASE_VERSION=""
store_with linux-mainstream-headers
chk store-standard-own "$(store_verdict)" "ok"
store_with linux-mainstream-performance-headers
chk store-standard-perf "$(store_verdict)" "warn"
RELEASE_VERSION=4.2.0
chk store-standard-perf-release "$(store_verdict)" "REJECTED"
MACBOOK_PROFILE=true
store_with linux-mainstream-headers
chk store-macbook-mainstream "$(store_verdict)" "REJECTED"
store_with proton-mainstream
chk store-macbook-clean "$(store_verdict)" "ok"

[[ $FAILS -eq 0 ]] && echo "build-kernels: all $N assertions PASS" || echo "build-kernels: $FAILS of $N FAILED"
exit $FAILS
