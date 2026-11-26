#!/usr/bin/env bash
# Drive install-gpu-drivers' NVIDIA steps and the live session's nouveau through
# every branch with fakes.
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
install_legacy_nvidia "Maxwell/Pascal/Volta"
chk legacy-unstaged-fallback "$FALLBACK" "1"
chk legacy-unstaged-nothing "${INST[*]:-none} ${LOCAL[*]:-none}" "none none"

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

[[ $FAILS -eq 0 ]] && echo "repair: all $N assertions PASS" || echo "repair: $FAILS of $N FAILED"
exit $FAILS
