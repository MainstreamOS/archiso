#!/usr/bin/env bash
# Drive install-gpu-drivers' NVIDIA steps, the live session's nouveau and fetch-online's
# NVIDIA pick through every branch with fakes.
set -uo pipefail
ARCHISO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIROOTFS="$ARCHISO_ROOT/configs/hyprland-dotfiles/airootfs"
SRC="$AIROOTFS/usr/local/bin/install-gpu-drivers"
source "${GPU_LIB:-$AIROOTFS/usr/local/lib/gpu-config.sh}"
# lift just the helper out of the installer, without running the installer
eval "$(awk '/^nvidia_ensure_module_for_target\(\) \{/,/^\}/' "$SRC")"
# The prebuilt driver unless a case says the DKMS build is installed; asking the
# fake pacman would count as a call.
OPEN_DKMS=0
_gpu_installed_nvidia_open_dkms() { [[ $OPEN_DKMS == 1 ]]; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MAINSTREAM_MODULES_DIR="$TMP/modules"

FAILS=0; N=0
info() { :; }; warn() { echo "      warn: $*"; }
note_failure() { GPU_FAILURES+=("$*"); }
chk() { N=$((N+1)); [[ "$2" == "$3" ]] || { echo "  FAIL [$1] got '$2' want '$3'"; FAILS=$((FAILS+1)); }; }

K=6.17.4-arch1-1
gpu_target_kernel() { echo "$K"; }

# ---- 1. module already there: no pacman at all
PAC=""; pacman() { PAC="$PAC $1"; return 0; }
_gpu_modinfo() { return 0; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk present-rc "$rc" "0"; chk present-nopacman "${PAC:-none}" "none"
chk present-nofail "${#GPU_FAILURES[@]}" "0"

# ---- 2. stranded, and the matching build exists once the db is refreshed.
# The db MUST be refreshed first: reinstalling the build already installed would
# lay the same files back under the same stale kernel.
PAC=(); pacman() { PAC+=("$*"); TRIES=$((TRIES+1)); return 0; }
TRIES=0; ATT=0
_gpu_modinfo() { ATT=$((ATT+1)); [[ $ATT -gt 1 ]]; }   # miss once, then present
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk refresh-rc "$rc" "0"
chk refresh-two-calls "$TRIES" "2"
chk refresh-db-first "$( [[ "${PAC[0]}" == "-Sy" ]] && echo yes || echo no )" "yes"
chk refresh-then-driver "$( [[ "${PAC[1]}" == *nvidia-open* ]] && echo yes || echo no )" "yes"
chk refresh-nofail "${#GPU_FAILURES[@]}" "0"

# ---- 3. no matching build published: DKMS fallback runs and succeeds
PAC=(); TRIES=0; ATT=0
pacman() { PAC+=("$*"); TRIES=$((TRIES+1)); return 0; }
_gpu_modinfo() { ATT=$((ATT+1)); [[ $ATT -gt 2 ]]; }   # miss, miss, then present after the swap
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk dkms-rc "$rc" "0"; chk dkms-tries "$TRIES" "6"
# The toolchain goes in on its own, so a refused swap cannot also cost the
# headers a build would need.
chk dkms-toolchain-alone "$( [[ "${PAC[2]}" == *linux-headers* && "${PAC[2]}" != *nvidia-open-dkms* ]] && echo yes || echo no )" "yes"
# Fetch the replacement DKMS driver before touching the prebuilt one.
chk dkms-fetches-first "$( [[ "${PAC[3]}" == *-Sw* && "${PAC[3]}" == *nvidia-open-dkms* ]] && echo yes || echo no )" "yes"
# The prebuilt driver must be removed explicitly: it conflicts with the DKMS
# one, and pacman answers its own conflict question with no when it cannot ask.
chk dkms-removes-prebuilt "$( [[ "${PAC[4]}" == *-Rdd* && "${PAC[4]}" == *nvidia-open* ]] && echo yes || echo no )" "yes"
chk dkms-then-swap "$( [[ "${PAC[5]}" == *nvidia-open-dkms* ]] && echo yes || echo no )" "yes"
chk dkms-swap-not-batched "$( [[ "${PAC[5]}" == *linux-headers* ]] && echo yes || echo no )" "no"
chk dkms-nofail "${#GPU_FAILURES[@]}" "0"

# ---- 4. nothing works: recorded as a failure, not silent
PAC=(); TRIES=0
pacman() { PAC+=("$*"); TRIES=$((TRIES+1)); return 0; }
_gpu_modinfo() { return 1; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk hopeless-rc "$rc" "1"; chk hopeless-tries "$TRIES" "6"
chk hopeless-recorded "$( [[ "${GPU_FAILURES[*]}" == *"no loadable module"* ]] && echo yes || echo no )" "yes"

# ---- 5. pacman itself fails: still recorded, never aborts the install
PAC=(); TRIES=0
pacman() { TRIES=$((TRIES+1)); return 1; }
_gpu_modinfo() { return 1; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk pacfail-rc "$rc" "1"; chk pacfail-recorded "${#GPU_FAILURES[@]}" "1"
chk pacfail-tried-all "$TRIES" "4"

# ---- 6. unknown target kernel: recorded, no blind pacman
TRIES=0; gpu_target_kernel() { echo ""; }
pacman() { TRIES=$((TRIES+1)); return 0; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk nokernel-rc "$rc" "1"; chk nokernel-nopacman "$TRIES" "0"
chk nokernel-recorded "$( [[ "${GPU_FAILURES[*]}" == *"which kernel"* ]] && echo yes || echo no )" "yes"

# ---- 7. the image's DKMS driver is installed: no prebuilt step and no swap,
# just the headers of the kernel's own package and a DKMS build for it
gpu_target_kernel() { echo "$K"; }
mkdir -p "$MAINSTREAM_MODULES_DIR/$K"; echo linux-mainstream > "$MAINSTREAM_MODULES_DIR/$K/pkgbase"
OPEN_DKMS=1; BUILT=0; PAC=(); DK=()
pacman() { PAC+=("$*"); return 0; }
dkms() {
    DK+=("$*")
    case "$1" in
        status) echo "nvidia/595.71, $K, x86_64: added" ;;
        install) BUILT=1 ;;
    esac
    return 0
}
_gpu_modinfo() { [[ $BUILT == 1 ]]; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk opendkms-rc "$rc" "0"; chk opendkms-nofail "${#GPU_FAILURES[@]}" "0"
chk opendkms-pacman-once "${#PAC[@]}" "1"
chk opendkms-own-headers "${PAC[0]:-}" "-S --noconfirm --needed linux-mainstream-headers dkms"
chk opendkms-no-prebuilt "$( [[ "${PAC[*]}" == *"-Sy"* || "${PAC[*]}" == *"-Rdd"* || "${PAC[*]}" == *"-Sw"* || "${PAC[*]}" == *"nvidia-open"* ]] && echo yes || echo no )" "no"
chk opendkms-builds-target "$( [[ " ${DK[*]} " == *"install -m nvidia -v 595.71 -k $K "* ]] && echo yes || echo no )" "yes"

# ---- 8. the same, with the headers already in place: they are in no repository,
# so only dkms is asked for, and a failed build is recorded
mkdir -p "$MAINSTREAM_MODULES_DIR/$K/build"
BUILT=0; PAC=(); DK=()
dkms() { DK+=("$*"); [[ $1 == status ]] && echo "nvidia/595.71, $K, x86_64: added"; [[ $1 != install ]]; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk opendkms-tree-rc "$rc" "1"
chk opendkms-tree-dkms-only "${PAC[*]}" "-S --noconfirm --needed dkms"
chk opendkms-tree-tried "$( [[ " ${DK[*]} " == *"install -m nvidia -v 595.71 -k $K "* ]] && echo yes || echo no )" "yes"
chk opendkms-tree-recorded "$( [[ "${GPU_FAILURES[*]}" == *"no loadable module"* ]] && echo yes || echo no )" "yes"
OPEN_DKMS=0; unset -f dkms

# ---- 9. no NVIDIA card: the image's module goes, by exact name, on either edition
eval "$(awk '/^remove_image_nvidia_module\(\) \{/,/^\}/' "$SRC")"
pacman() {
    local p
    if [[ $1 == -Qq ]]; then
        for p in $INSTALLED; do [[ $p == "$2" ]] && { echo "$p"; return 0; }; done
        # the DKMS build answers for the prebuilt name it provides
        [[ $2 == nvidia-open && " $INSTALLED " == *" nvidia-open-dkms "* ]] && { echo nvidia-open-dkms; return 0; }
        return 1
    fi
    PAC+=("$*")
}
INSTALLED="nvidia-open-dkms nvidia-utils"; PAC=()
remove_image_nvidia_module
chk nonv-open-dkms "${PAC[*]:-none}" "-R --noconfirm nvidia-open-dkms"
INSTALLED="nvidia-580xx-dkms nvidia-580xx-utils"; PAC=()
remove_image_nvidia_module
chk nonv-legacy-dkms "${PAC[*]:-none}" "-R --noconfirm nvidia-580xx-dkms"
INSTALLED="mesa"; PAC=()
remove_image_nvidia_module
chk nonv-nothing "${PAC[*]:-none}" "none"

# ---- 10. a legacy card builds the staged DKMS driver against the image's kernel
# headers, with no Arch kernel or headers asked for beside it
eval "$(awk '/^install_legacy_nvidia\(\) \{/,/^\}/' "$SRC")"
NVIDIA_LOCAL_PKGS=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx)
STAGED=1
find_local_pkgs() { [[ $STAGED == 1 ]] && echo "/usr/local/share/pkgs/$1-580.95.05-1-x86_64.pkg.tar.zst"; }
install_pkgs() { INST+=("$@"); }
install_pkgs_opt() { INST+=("$@"); }
install_local_pkgs() { LOCAL+=("$@"); }
detect_dkms_version() { echo 580.95.05; }
target_dkms_install() { DKI+=("$*"); }
legacy_nvidia_fallback() { FALLBACK=1; }
INST=(); LOCAL=(); DKI=(); FALLBACK=0; GPU_FAILURES=()
install_legacy_nvidia "Maxwell/Pascal/Volta"
chk legacy-no-arch-kernel "$( [[ " ${INST[*]} " == *" linux "* || " ${INST[*]} " == *" linux-headers "* ]] && echo yes || echo no )" "no"
chk legacy-dkms "$( [[ " ${INST[*]} " == *" dkms "* ]] && echo yes || echo no )" "yes"
chk legacy-local-set "${LOCAL[*]}" "${NVIDIA_LOCAL_PKGS[*]}"
chk legacy-builds "${DKI[*]:-none}" "nvidia 580.95.05"
chk legacy-nofail "${#GPU_FAILURES[@]}" "0"
STAGED=0; INST=(); LOCAL=(); FALLBACK=0
# Nothing staged, as on the standard edition: the branch comes from the
# repository through the shared library, run as the chroot's root.
eval "$(awk '/^install_repo_legacy_nvidia\(\) \{/,/^\}/' "$SRC")"
GPU_INSTALL_LIB="$TMP/legacy-lib.sh"
cat > "$GPU_INSTALL_LIB" <<'LIB'
gpu_nvidia_install_legacy() {
    LIB_CALLS+=("install sudo=${GPU_SUDO-unset}")
    [[ $LIB_RC == 1 ]] && NVIDIA_DRIVER_FAMILY=nouveau
    return "$LIB_RC"
}
LIB
repo_legacy() {  # repo_legacy <family> <library rc>
    NVIDIA_DRIVER_FAMILY="$1"; LIB_RC="$2"; INST=(); LOCAL=(); LIB_CALLS=(); FALLBACK=0; GPU_FAILURES=()
    install_legacy_nvidia "label"
}
repo_legacy nvidia-580xx 0
chk repo-580-library "${LIB_CALLS[*]:-none}" "install sudo="
chk repo-580-extras "${INST[*]:-none}" "libva-nvidia-driver libva-utils linux-firmware-nvidia"
chk repo-580-no-fallback "$FALLBACK ${LOCAL[*]:-none}" "0 none"
# It built for no kernel: the library took it back off, nouveau's userspace goes in.
repo_legacy nvidia-580xx 1
chk repo-buildfail-mesa "${INST[*]:-none}" "mesa lib32-mesa"
chk repo-buildfail-no-fallback "$FALLBACK" "0"
# Not offered or not downloadable: the offline fallback.
repo_legacy nvidia-580xx 2
chk repo-offline-fallback "$FALLBACK ${INST[*]:-none}" "1 none"
GPU_INSTALL_LIB="$TMP/no-such-lib.sh"
repo_legacy nvidia-580xx 0
chk repo-nolib-fallback "$FALLBACK ${LIB_CALLS[*]:-none}" "1 none"

# The offline fallback: nouveau now, a note for the system update, and no
# word about another edition.
eval "$(awk '/^legacy_nvidia_fallback\(\) \{/,/^\}/' "$SRC")"
remove_nvidia_driver() { REMOVED=1; }
gpu_nvidia_mark_pending() { LIB_CALLS+=("pending $NVIDIA_DRIVER_FAMILY sudo=${GPU_SUDO-unset}"); }
NVIDIA_DRIVER_FAMILY=nvidia-580xx; INST=(); LIB_CALLS=(); REMOVED=0; GPU_FAILURES=()
legacy_nvidia_fallback "Maxwell"
chk fallback-nouveau "${INST[*]:-none} $REMOVED" "mesa lib32-mesa 1"
chk fallback-pending "${LIB_CALLS[*]:-none}" "pending nvidia-580xx sudo="
chk fallback-says-update "$( [[ "${GPU_FAILURES[*]}" == *"installs with the next system update once the computer is online"* ]] && echo yes || echo no )" "yes"
chk fallback-no-edition "$( [[ "${GPU_FAILURES[*]}" == *edition* || "${GPU_FAILURES[*]}" == *ISO* ]] && echo yes || echo no )" "no"
unset -f gpu_nvidia_mark_pending

# ---- 11. every chosen kernel, Arch's included, gets the module or comes back out
eval "$(awk '/^nvidia_chosen_kernel\(\) \{/,/^\}/' "$SRC")"
export MAINSTREAM_MODULES_DIR="$TMP/chosen-modules"
for _r in 7.3.6-1-mainstream:linux-mainstream 6.18.1-arch1-1:linux; do
    mkdir -p "$MAINSTREAM_MODULES_DIR/${_r%%:*}"
    : > "$MAINSTREAM_MODULES_DIR/${_r%%:*}/vmlinuz"
    echo "${_r#*:}" > "$MAINSTREAM_MODULES_DIR/${_r%%:*}/pkgbase"
done
mkdir -p "$MAINSTREAM_MODULES_DIR/7.3.6-1-mainstream/updates/dkms"
: > "$MAINSTREAM_MODULES_DIR/7.3.6-1-mainstream/updates/dkms/nvidia.ko.zst"
_gpu_module_dirs() { printf '%s\n' "$MAINSTREAM_MODULES_DIR"/*/; }
_gpu_modinfo() { return 1; }
_gpu_module_file() { [[ -n "$(find "$MAINSTREAM_MODULES_DIR/$1" -name 'nvidia.ko*' -print -quit 2>/dev/null)" ]]; }
GPU_INSTALL_LIB="$TMP/gpu-driver-install.sh"
echo 'gpu_nvidia_modules_for_added_kernel() { ADDED+=("$1"); }' > "$GPU_INSTALL_LIB"
INSTALLED="linux-mainstream linux-mainstream-headers linux linux-headers"; RM_RC=0
pacman() {
    local p
    if [[ $1 == -Qq ]]; then
        for p in $INSTALLED; do [[ $p == "$2" ]] && { echo "$p"; return 0; }; done
        return 1
    fi
    PAC+=("$*")
    return "$RM_RC"
}
PAC=(); ADDED=(); GPU_FAILURES=()
nvidia_chosen_kernel linux-mainstream
chk chosen-ready-asked "${ADDED[*]:-none}" "linux-mainstream"
chk chosen-ready-kept "${PAC[*]:-none}" "none"
PAC=(); ADDED=(); GPU_FAILURES=()
nvidia_chosen_kernel linux-mainstream-performance
chk chosen-absent-untouched "${ADDED[*]:-none} ${PAC[*]:-none}" "none none"
PAC=(); ADDED=(); GPU_FAILURES=()
nvidia_chosen_kernel linux
chk chosen-arch-asked "${ADDED[*]:-none}" "linux"
chk chosen-arch-removed "${PAC[*]:-none}" "-Rns --noconfirm linux linux-headers"
chk chosen-arch-nofail "${#GPU_FAILURES[@]}" "0"
PAC=(); ADDED=(); GPU_FAILURES=(); RM_RC=1
nvidia_chosen_kernel linux
chk chosen-stuck-recorded "$( [[ "${GPU_FAILURES[*]}" == *"choose another kernel in the boot menu"* ]] && echo yes || echo no )" "yes"
RM_RC=0

# ---- 12. an older card on the standard edition, end to end: install-gpu-drivers'
# own steps, the real shared library, and a stand-in pacman and DKMS
eval "$(awk '/^install_legacy_nvidia\(\) \{/,/^\}/' "$SRC")"
eval "$(awk '/^legacy_nvidia_fallback\(\) \{/,/^\}/' "$SRC")"
eval "$(awk '/^remove_nvidia_driver\(\) \{/,/^\}/' "$SRC")"
export MAINSTREAM_MODULES_DIR="$TMP/e2e-modules"
KM=7.3.6-1-mainstream
GPU_NVIDIA_PENDING="$TMP/e2e-state/nvidia-driver-pending"
# The real library, then the stand-ins for what it would read off this machine.
GPU_INSTALL_LIB="$TMP/e2e-lib.sh"
printf 'source %q\n_gpu_kernel_headers_present() { [[ -d "$MAINSTREAM_MODULES_DIR/$1/build" ]]; }\n' \
    "$AIROOTFS/usr/local/lib/gpu-driver-install.sh" > "$GPU_INSTALL_LIB"
set_of() {
    case "$1" in
        580xx) echo "nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx" ;;
    esac
}
has_pkg() { [[ " $INSTALLED " == *" $1 "* ]]; }
pacman() {
    local op="$1" p t pkgs=()
    shift
    for p in "$@"; do [[ "$p" == -* ]] || pkgs+=("$p"); done
    case "$op" in
        -Q|-Qq) has_pkg "${pkgs[0]}" && echo "${pkgs[0]}" ;;
        -Si) [[ " $REPO " == *" ${pkgs[0]} "* ]] ;;
        -Sw) echo "$op ${pkgs[*]}" >> "$TMP/e2e-pac.log"
             for p in "${pkgs[@]}"; do [[ " $REPO " == *" $p "* ]] || return 1; done ;;
        -Rdd|-Rns|-R)
            echo "$op ${pkgs[*]}" >> "$TMP/e2e-pac.log"
            for p in "${pkgs[@]}"; do
                INSTALLED="${INSTALLED/ $p / }"
                [[ "$p" == *-dkms ]] && find "$MAINSTREAM_MODULES_DIR" -name 'nvidia.ko*' -delete
            done
            return 0 ;;
        -S)
            echo "$op ${pkgs[*]}" >> "$TMP/e2e-pac.log"
            for p in "${pkgs[@]}"; do
                [[ " $REPO " == *" $p "* ]] || return 1
                # The conflict question answers itself with no.
                if [[ "$p" == nvidia-*xx-* ]] && { has_pkg nvidia-utils || has_pkg nvidia-open-dkms; }; then return 1; fi
            done
            for p in "${pkgs[@]}"; do
                has_pkg "$p" || INSTALLED+="$p "
                if [[ "$p" == nvidia-*xx-dkms && $DKMS_OK == 1 ]]; then
                    for t in "$MAINSTREAM_MODULES_DIR"/*/build; do : > "${t%/build}/nvidia.ko.zst"; done
                fi
            done ;;
        *) echo "unexpected pacman $op" >> "$TMP/e2e-pac.log"; return 1 ;;
    esac
}
dkms() {
    case "$1" in
        status) [[ "$INSTALLED" == *-dkms* ]] && echo "nvidia/580.196.07, $KM, x86_64: added" ;;
        install) [[ $DKMS_OK == 1 ]] ;;
    esac
}
find_local_pkgs() { :; }
e2e() {  # e2e <generation> <offered> <dkms builds>
    rm -rf "${MAINSTREAM_MODULES_DIR:?}" "${TMP:?}/e2e-state"; : > "$TMP/e2e-pac.log"
    mkdir -p "$MAINSTREAM_MODULES_DIR/$KM/build" "$TMP/e2e-state"
    : > "$MAINSTREAM_MODULES_DIR/$KM/vmlinuz"; echo linux-mainstream > "$MAINSTREAM_MODULES_DIR/$KM/pkgbase"
    : > "$MAINSTREAM_MODULES_DIR/$KM/nvidia.ko.zst"
    INSTALLED=" linux-mainstream linux-mainstream-headers dkms nvidia-open-dkms nvidia-utils "
    REPO="linux-mainstream linux-mainstream-headers dkms egl-wayland"
    [[ "$2" == offered ]] && REPO+=" $(set_of 580xx)"
    DKMS_OK="$3"; NVIDIA_GEN="$1"; INST=(); GPU_FAILURES=()
    gpu_classify_nvidia_driver
    install_legacy_nvidia "label" >/dev/null 2>&1
}
_gpu_installed_nvidia_branch() { local b; for b in 580xx 470xx 390xx; do has_pkg "nvidia-$b-dkms" && { printf '%s' "$b"; return 0; }; done; printf ''; }
e2e maxwell offered 1
chk e2e-online-sequence "$(cat "$TMP/e2e-pac.log")" "-Sw $(set_of 580xx)
-Rdd nvidia-open-dkms nvidia-utils
-S linux-mainstream linux-mainstream-headers dkms
-S $(set_of 580xx) egl-wayland"
chk e2e-online-module "$(nvidia_module_present $KM && echo yes || echo no)" "yes"
chk e2e-online-family "$NVIDIA_DRIVER_FAMILY $(has_pkg nvidia-utils && echo mainline-left)" "nvidia-580xx "
chk e2e-online-vaapi "${INST[*]:-none}" "libva-nvidia-driver libva-utils linux-firmware-nvidia"
chk e2e-online-nofail "${#GPU_FAILURES[@]}" "0"
chk e2e-online-no-pending "$( [[ -e "$GPU_NVIDIA_PENDING" ]] && echo there || echo none )" "none"
e2e maxwell missing 1
chk e2e-offline-nouveau "${INST[*]:-none}" "mesa lib32-mesa"
chk e2e-offline-mainline-off "$(cat "$TMP/e2e-pac.log")" "-Rns nvidia-open-dkms nvidia-utils"
chk e2e-offline-pending "$(cat "$GPU_NVIDIA_PENDING" 2>/dev/null)" "nvidia-580xx"
chk e2e-offline-said "$( [[ "${GPU_FAILURES[*]}" == *"next system update"* ]] && echo yes || echo no )" "yes"
# The module does not build for the image's kernel: nothing NVIDIA is left, the
# card falls to nouveau and the kernel stays, since no kernel has a module.
e2e maxwell offered 0
chk e2e-buildfail-nothing-left "$INSTALLED" " linux-mainstream linux-mainstream-headers dkms egl-wayland "
chk e2e-buildfail-family "$NVIDIA_DRIVER_FAMILY" "nouveau"
chk e2e-buildfail-nouveau "${INST[*]:-none}" "mesa lib32-mesa"
chk e2e-buildfail-no-pending "$( [[ -e "$GPU_NVIDIA_PENDING" ]] && echo there || echo none )" "none"
chk e2e-buildfail-said "$( [[ "${GPU_FAILURES[*]}" == *"nvidia-580xx did not build for any installed kernel"* ]] && echo yes || echo no )" "yes"
chk e2e-buildfail-kernel-ready "$(gpu_kernel_nvidia_ready linux-mainstream && echo yes || echo no)" "yes"
# Kepler and Fermi stay on nouveau, also where the legacy edition's image left its
# 580xx on the target: that driver cannot drive them and comes off with the rest.
for _g in kepler fermi; do
    : > "$TMP/e2e-pac.log"
    INSTALLED=" linux-mainstream dkms $(set_of 580xx) "; NVIDIA_GEN="$_g"
    gpu_classify_nvidia_driver
    chk "e2e-$_g-nouveau" "$NVIDIA_DRIVER_FAMILY ${#NVIDIA_LOCAL_PKGS[@]}" "nouveau 0"
    remove_nvidia_driver >/dev/null 2>&1
    chk "e2e-$_g-edition-driver-off" "$(cat "$TMP/e2e-pac.log")" "-Rns $(set_of 580xx)"
done
# A Maxwell card there keeps the edition's driver.
INSTALLED=" linux-mainstream dkms $(set_of 580xx) "; NVIDIA_GEN=maxwell
gpu_classify_nvidia_driver
chk e2e-maxwell-edition "$NVIDIA_DRIVER_FAMILY" "nvidia-580xx"
unset -f pacman dkms find_local_pkgs _gpu_installed_nvidia_branch

# ---- 13. the live session: nouveau for an older card that drives the screen
LIVE="$AIROOTFS/usr/local/bin/live-nouveau"
mkdir -p "$TMP/live-bin" "$TMP/live-drm"
printf '#!/bin/sh\necho "modprobe $*" >> "%s"\nexit "${MODPROBE_RC:-0}"\n' "$TMP/live.log" > "$TMP/live-bin/modprobe"
printf '#!/bin/sh\necho "udevadm $*" >> "%s"\n' "$TMP/live.log" > "$TMP/live-bin/udevadm"
chmod +x "$TMP/live-bin/modprobe" "$TMP/live-bin/udevadm"
# The real library, reading fixtures instead of this machine.
cat > "$TMP/live-lib.sh" <<LIB
source "$AIROOTFS/usr/local/lib/gpu-config.sh"
_gpu_lspci_nn() { printf '%s\n' "\$FIX_LSPCI"; }
_gpu_lspci() { printf '%s\n' "\$FIX_LSPCI"; }
_gpu_sys_vendor() { :; }
_gpu_installed_nvidia_branch() { printf '%s' "\${FIX_BRANCH:-}"; }
LIB
live_pci() {  # live_pci <slot,vendor,boot_vga>...
    local d slot vendor boot e
    rm -rf "${TMP:?}/live-pci"; mkdir -p "$TMP/live-pci"
    for e in "$@"; do
        IFS=, read -r slot vendor boot <<<"$e"
        d="$TMP/live-pci/$slot"; mkdir -p "$d"
        echo 0x030000 > "$d/class"; echo "$vendor" > "$d/vendor"; echo "$boot" > "$d/boot_vga"
    done
}
live() {  # live <lspci>; prints what ran, then the notice
    : > "$TMP/live.log"; rm -f "$TMP/live-notice"
    FIX_LSPCI="$1" GPU_LIB="$TMP/live-lib.sh" MAINSTREAM_NOUVEAU_NOTICE="$TMP/live-notice" \
        GPU_PCI_DEVICES_PATH="$TMP/live-pci" GPU_DRM_PATH="$TMP/live-drm" PATH="$TMP/live-bin:$PATH" \
        bash "$LIVE" >/dev/null 2>&1
    printf '%s|%s' "$(tr '\n' ';' < "$TMP/live.log")" "$(cat "$TMP/live-notice" 2>/dev/null)"
}
GTX1060="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)"
GT710="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
RTX2080="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87] (rev a1)"
OPTIMUS="00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 630 [8086:591b] (rev 04)
01:00.0 3D controller [0302]: NVIDIA Corporation GP107M [GeForce GTX 1050 Mobile] [10de:1c8d] (rev a1)"
live_pci 0000:01:00.0,0x10de,1
chk live-maxwell "$(live "$GTX1060")" "modprobe nouveau;udevadm settle --timeout=15;|maxwell loaded"
chk live-kepler "$(live "$GT710")" "modprobe nouveau;udevadm settle --timeout=15;|kepler loaded"
chk live-turing "$(live "$RTX2080")" "|"
chk live-legacy-edition "$(FIX_BRANCH=580xx live "$GTX1060")" "|"
chk live-failed "$(MODPROBE_RC=1 live "$GT710")" "modprobe nouveau;|kepler failed"
live_pci 0000:00:02.0,0x8086,1 0000:01:00.0,0x10de,0
chk live-hybrid-igpu "$(live "$OPTIMUS")" "|"
live_pci 0000:00:02.0,0x8086,0 0000:01:00.0,0x10de,1
chk live-hybrid-mux "$(live "$OPTIMUS")" "modprobe nouveau;udevadm settle --timeout=15;|maxwell loaded"

# ---- 14. fetch-online asks for the branch an older card needs, when the image lacks it
FETCH="$AIROOTFS/usr/local/bin/mainstream-fetch-online"
printf '#!/bin/sh\nexit 22\n' > "$TMP/live-bin/curl"; chmod +x "$TMP/live-bin/curl"
fetch() {  # fetch <lspci> <args...>; prints fetch-online's own lines
    local lspci="$1"; shift
    FIX_LSPCI="$lspci" GPU_LIB="$TMP/live-lib.sh" PATH="$TMP/live-bin:$PATH" \
        bash "$FETCH" "$TMP/fetch-root" "$@" 2>&1 | sed 's/^\[fetch-online\] //' | tr '\n' ';'
}
mkdir -p "$TMP/fetch-root"
chk fetch-maxwell "$(fetch "$GTX1060" --nvidia)" \
    "the NVIDIA card needs nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx.;could not reach the [mainstream] repository; using what the image carries.;"
# Kepler stays on nouveau: only the kernel is fetched.
chk fetch-kepler-with-kernel "$(fetch "$GT710" --kernel linux-mainstream-performance --nvidia)" \
    "could not reach the [mainstream] repository; using what the image carries.;"
chk fetch-kepler "$(fetch "$GT710" --nvidia)" "nothing to fetch.;"
chk fetch-turing "$(fetch "$RTX2080" --nvidia)" "nothing to fetch.;"
chk fetch-not-asked "$(fetch "$GT710")" "nothing to fetch.;"
# The legacy edition stages the branch in the store: nothing to download.
mkdir -p "$TMP/fetch-root/usr/local/share/pkgs"
: > "$TMP/fetch-root/usr/local/share/pkgs/nvidia-580xx-dkms-580.196.07-1-x86_64.pkg.tar.zst"
chk fetch-staged "$(fetch "$GTX1060" --nvidia)" "nothing to fetch.;"

[[ $FAILS -eq 0 ]] && echo "repair: all $N assertions PASS" || echo "repair: $FAILS of $N FAILED"
exit $FAILS
