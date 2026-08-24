#!/usr/bin/env bash
# Drive nvidia_ensure_module_for_target through every branch with fakes.
set -uo pipefail
SRC=~/Documents/GitHub/archiso/configs/hyprland-dotfiles/airootfs/usr/local/bin/install-gpu-drivers
source ~/Documents/GitHub/dots-hyprland/sdata/lib/gpu-config.sh
# lift just the helper out of the installer, without running the installer
eval "$(awk '/^nvidia_ensure_module_for_target\(\) \{/,/^\}/' "$SRC")"

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
chk dkms-rc "$rc" "0"; chk dkms-tries "$TRIES" "5"
# The toolchain goes in on its own, so a refused swap cannot also cost the
# headers a build would need.
chk dkms-toolchain-alone "$( [[ "${PAC[2]}" == *linux-headers* && "${PAC[2]}" != *nvidia-open-dkms* ]] && echo yes || echo no )" "yes"
# The prebuilt driver must be removed explicitly: it conflicts with the DKMS
# one, and pacman answers its own conflict question with no when it cannot ask.
chk dkms-removes-prebuilt "$( [[ "${PAC[3]}" == *-Rdd* && "${PAC[3]}" == *nvidia-open* ]] && echo yes || echo no )" "yes"
chk dkms-then-swap "$( [[ "${PAC[4]}" == *nvidia-open-dkms* ]] && echo yes || echo no )" "yes"
chk dkms-swap-not-batched "$( [[ "${PAC[4]}" == *linux-headers* ]] && echo yes || echo no )" "no"
chk dkms-nofail "${#GPU_FAILURES[@]}" "0"

# ---- 4. nothing works: recorded as a failure, not silent
PAC=(); TRIES=0
pacman() { PAC+=("$*"); TRIES=$((TRIES+1)); return 0; }
_gpu_modinfo() { return 1; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk hopeless-rc "$rc" "1"; chk hopeless-tries "$TRIES" "5"
chk hopeless-recorded "$( [[ "${GPU_FAILURES[*]}" == *"no loadable module"* ]] && echo yes || echo no )" "yes"

# ---- 5. pacman itself fails: still recorded, never aborts the install
PAC=(); TRIES=0
pacman() { TRIES=$((TRIES+1)); return 1; }
_gpu_modinfo() { return 1; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk pacfail-rc "$rc" "1"; chk pacfail-recorded "${#GPU_FAILURES[@]}" "1"
chk pacfail-tried-all "$TRIES" "5"

# ---- 6. unknown target kernel: recorded, no blind pacman
TRIES=0; gpu_target_kernel() { echo ""; }
pacman() { TRIES=$((TRIES+1)); return 0; }
GPU_FAILURES=(); nvidia_ensure_module_for_target; rc=$?
chk nokernel-rc "$rc" "1"; chk nokernel-nopacman "$TRIES" "0"
chk nokernel-recorded "$( [[ "${GPU_FAILURES[*]}" == *"which kernel"* ]] && echo yes || echo no )" "yes"

[[ $FAILS -eq 0 ]] && echo "repair: all $N assertions PASS" || echo "repair: $FAILS of $N FAILED"
exit $FAILS
