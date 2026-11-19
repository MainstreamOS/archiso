#!/usr/bin/env bash
# Unit tests for Phase 1 (Calamares password policy, security packages, Limine
# Secure Boot enrollment preservation) and Phase 2 (encrypted & plaintext Btrfs
# @swap/swapfile hibernation setup in post-install-boot).
set -uo pipefail

ARCHISO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIROOTFS="$ARCHISO_ROOT/configs/hyprland-dotfiles/airootfs"
USERS_CONF="$AIROOTFS/etc/calamares/modules/users.conf"
PART_CONF="$AIROOTFS/etc/calamares/modules/partition.conf"
PKGS_FILE="$ARCHISO_ROOT/configs/hyprland-dotfiles/packages.x86_64"
COMMON_SH="$AIROOTFS/usr/local/lib/mainstream-postinstall-common.sh"
GPU_LIB="$AIROOTFS/usr/local/lib/gpu-config.sh"
POST_BOOT="$AIROOTFS/usr/local/bin/post-install-boot"

FAILS=0
N=0
chk() {
    N=$((N + 1))
    if [[ "$2" != "$3" ]]; then
        echo "  FAIL [$1] got '$2' want '$3'"
        FAILS=$((FAILS + 1))
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1. Calamares users.conf password requirements
# ---------------------------------------------------------------------------
chk users-allow-weak \
    "$(awk '/^allowWeakPasswords:/ {print $2}' "$USERS_CONF")" "true"
chk users-allow-weak-default \
    "$(awk '/^allowWeakPasswordsDefault:/ {print $2}' "$USERS_CONF")" "false"
chk users-min-length \
    "$(awk '/^[[:space:]]*minLength:/ {print $2}' "$USERS_CONF")" "8"
chk users-max-length \
    "$(awk '/^[[:space:]]*maxLength:/ {print $2}' "$USERS_CONF")" "-1"
chk users-pwquality-minlen \
    "$(grep -Eq '^[[:space:]]*-[[:space:]]*minlen=8([[:space:]]|$)' "$USERS_CONF" && echo yes || echo no)" "yes"
chk users-pwquality-minclass \
    "$(grep -Eq '^[[:space:]]*-[[:space:]]*minclass=2([[:space:]]|$)' "$USERS_CONF" && echo yes || echo no)" "yes"
chk users-shell-intact \
    "$(awk '/^[[:space:]]*shell:/ {print $2}' "$USERS_CONF")" "/usr/bin/zsh"
chk users-sudoers-intact \
    "$(awk '/^sudoersGroup:/ {print $2}' "$USERS_CONF")" "wheel"

# ---------------------------------------------------------------------------
# 2. packages.x86_64 ships sbctl, libfido2, tpm2-tss
# ---------------------------------------------------------------------------
for pkg in sbctl libfido2 tpm2-tss; do
    chk "pkg-$pkg" \
        "$(grep -qxF "$pkg" "$PKGS_FILE" && echo yes || echo no)" "yes"
done

# ---------------------------------------------------------------------------
# 3. partition.conf swap comment documents @swap/swapfile and noauto safety
# ---------------------------------------------------------------------------
chk part-conf-mentions-swapfile \
    "$(grep -q '@swap' "$PART_CONF" && echo yes || echo no)" "yes"
chk part-conf-mentions-noauto \
    "$(grep -q 'noauto' "$PART_CONF" && echo yes || echo no)" "yes"

# ---------------------------------------------------------------------------
# 4. write_limine_defaults preserves ENABLE_ENROLL_LIMINE_CONFIG and ESP_PATH
# ---------------------------------------------------------------------------
# Extract write_limine_defaults so we can test it without exec 2>&1 side-effects.
eval "$(awk '/^write_limine_defaults\(\)/,/^\}/' "$COMMON_SH")"

LIMINE_DEFAULTS_FILE="$TMP/etc/default/limine"
mkdir -p "$(dirname "$LIMINE_DEFAULTS_FILE")"
cat > "$LIMINE_DEFAULTS_FILE" << 'EOF'
TARGET_OS_NAME="Mainstream OS\\"
ESP_PATH=/boot/efi
ENABLE_ENROLL_LIMINE_CONFIG=yes
EOF

# 4a. Calling write_limine_defaults with no arguments preserves both keys.
write_limine_defaults
chk limine-preserve-esp \
    "$(grep -qxF 'ESP_PATH=/boot/efi' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"
chk limine-preserve-enroll \
    "$(grep -qxF 'ENABLE_ENROLL_LIMINE_CONFIG=yes' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"
chk limine-preserve-uki \
    "$(grep -qxF 'ENABLE_UKI=yes' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"

# 4b. Calling write_limine_defaults with an explicit ESP path updates ESP_PATH
# while still preserving ENABLE_ENROLL_LIMINE_CONFIG=yes.
write_limine_defaults "/efi"
chk limine-override-esp \
    "$(grep -qxF 'ESP_PATH=/efi' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"
chk limine-keep-enroll-on-esp-override \
    "$(grep -qxF 'ENABLE_ENROLL_LIMINE_CONFIG=yes' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"

# 4c. Fresh file without ENABLE_ENROLL_LIMINE_CONFIG omits that key cleanly.
rm -f "$LIMINE_DEFAULTS_FILE"
write_limine_defaults "/boot/efi"
chk limine-fresh-esp \
    "$(grep -qxF 'ESP_PATH=/boot/efi' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "yes"
chk limine-fresh-no-enroll \
    "$(grep -q '^ENABLE_ENROLL_LIMINE_CONFIG=' "$LIMINE_DEFAULTS_FILE" && echo yes || echo no)" "no"

# ---------------------------------------------------------------------------
# 5. _apply_hibernation_policy / _setup_btrfs_swapfile_hibernation
# ---------------------------------------------------------------------------
# Source gpu-config.sh (for cmdline_upsert) and post-install-boot (functions only).
# shellcheck source=/dev/null
source "$GPU_LIB"
GPU_SUDO=''
info() { :; }
warn() { WARN_MSGS+=("$*"); }
log()  { :; }
# shellcheck source=/dev/null
POST_BOOT_SOURCE_ONLY=1 source "$POST_BOOT"

# Mock tools: btrfs, mount, umount, findmnt, lsblk, blkid, df
btrfs() {
    BTRFS_CALLS+=("$*")
    case "$1 ${2:-}" in
        "subvolume create")
            if [[ "${MOCK_SUBVOL_FAIL:-0}" == 1 ]]; then
                return 1
            fi
            local target="$3"
            mkdir -p "$target"
            mkdir -p "$BTRFS_TOP_ROOT/@swap"
            CREATED_SUBVOLS+=("$target")
            return 0
            ;;
        "filesystem mkswapfile")
            # btrfs filesystem mkswapfile --size <size> --uuid clear <path>
            local sz="$4" path="$7"
            if [[ "${MOCK_MKSWAPFILE_FAIL:-0}" == 1 ]]; then
                mkdir -p "$(dirname "$path")"
                printf 'PARTIAL' > "$path"
                return 1
            fi
            MKSWAPFILE_SIZES+=("$sz")
            MKSWAPFILE_PATHS+=("$path")
            mkdir -p "$(dirname "$path")"
            printf 'SWAPFILE(%s)\n' "$sz" > "$path"
            return 0
            ;;
        "inspect-internal map-swapfile")
            # btrfs inspect-internal map-swapfile -r <path>
            printf '%s\n' "${MOCK_RESUME_OFFSET}"
            return 0
            ;;
    esac
    return 1
}

mount() {
    MOUNT_CALLS+=("$*")
    local last="${!#}"
    if [[ "$*" == *"subvolid=5"* ]]; then
        if [[ "${MOCK_MOUNT_TOP_FAIL:-0}" == 1 ]]; then
            return 1
        fi
        CURRENT_TOP_MNT="$last"
        if [[ -d "$BTRFS_TOP_ROOT/@swap" ]]; then
            mkdir -p "$last/@swap"
        fi
        return 0
    fi
    if [[ "$*" == *"subvol=/@swap"* ]]; then
        SWAP_DIR_MOUNTED=1
        return 0
    fi
    return 0
}

umount() {
    UMOUNT_CALLS+=("$*")
    if [[ -n "${CURRENT_TOP_MNT:-}" && "$1" == "$CURRENT_TOP_MNT" ]]; then
        rm -rf "$CURRENT_TOP_MNT/@swap" 2>/dev/null || true
        CURRENT_TOP_MNT=""
    fi
    if [[ "$1" == "$POST_BOOT_SWAP_DIR" ]]; then
        SWAP_DIR_MOUNTED=0
    fi
    return 0
}

findmnt() {
    if [[ "$*" == *"--mountpoint"* ]]; then
        [[ "${SWAP_DIR_MOUNTED:-0}" == 1 ]]
        return $?
    fi
    if [[ "$*" == *"--fstab"* ]]; then
        local nonoauto=0
        [[ "$*" == *"nonoauto"* ]] && nonoauto=1
        local out
        out=$(awk -v nono="$nonoauto" '
            $1 !~ /^#/ && $3 == "swap" {
                if (nono && $4 ~ /(^|,)noauto(,|$)/) next
                print $1
            }
        ' "$POST_BOOT_FSTAB" 2>/dev/null)
        [[ -n "$out" ]] || return 1
        printf '%s\n' "$out"
        return 0
    fi
    return 1
}

blkid() {
    if [[ "$*" == *"-s UUID -o value"* ]]; then
        printf '%s\n' "$MOCK_FS_UUID"
        return 0
    fi
    return 1
}

df() {
    printf 'Filesystem 1048576-blocks Used Available Capacity Mounted on\n'
    printf '/dev/root 100000 20000 %s 20%% /\n' "$MOCK_AVAIL_MIB"
    return 0
}

lsblk() {
    case "$*" in
        "-dno PKNAME "*)
            printf '%s\n' "$MOCK_DISK"
            ;;
        "-nlpo NAME,PARTTYPE,PARTFLAGS "*)
            [[ -n "$MOCK_GPT_SWAPS" ]] && printf '%s\n' "$MOCK_GPT_SWAPS"
            ;;
        "-dno TYPE,FSTYPE "*)
            printf '%s\n' "$MOCK_SWAP_TYPE_FSTYPE"
            ;;
        "-dno PARTUUID "*)
            printf '%s\n' "$MOCK_SWAP_PARTUUID"
            ;;
        "-dno UUID "*)
            printf '%s\n' "$MOCK_FS_UUID"
            ;;
    esac
    return 0
}

reset_case() {
    local case_dir="$TMP/case-$1"
    rm -rf "$case_dir"
    mkdir -p "$case_dir"
    export TMPDIR="$case_dir"
    BTRFS_TOP_ROOT="$case_dir/btrfs-top"
    mkdir -p "$BTRFS_TOP_ROOT"

    POST_BOOT_FSTAB="$case_dir/fstab"
    POST_BOOT_NO_HIB_DROPIN="$case_dir/50-mainstream-no-hibernate.conf"
    POST_BOOT_SWAP_DIR="$case_dir/swap"
    POST_BOOT_ROOT_MOUNT="$case_dir"
    KERNEL_CMDLINE="$case_dir/cmdline"
    PROC_MEMINFO="$case_dir/meminfo"
    SWAPFILE_HEADROOM_MIB=16384

    # Default: 16 GiB RAM (16777216 KiB -> 16384 MiB), 64 GiB free (65536 MiB)
    printf 'MemTotal:       16777216 kB\n' > "$PROC_MEMINFO"
    MOCK_AVAIL_MIB=65536
    MOCK_FS_UUID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    MOCK_RESUME_OFFSET="3481600"
    MOCK_DISK="/dev/nvme0n1"
    MOCK_GPT_SWAPS=""
    MOCK_SWAP_TYPE_FSTYPE="part swap"
    MOCK_SWAP_PARTUUID="99999999-0000-4000-8000-111111111111"

    DISK_HOST_DEV="/dev/nvme0n1p2"
    ROOT_PART_DEV="/dev/mapper/luks-1234"
    ROOT_FSTYPE="btrfs"
    ROOT_SPEC="rd.luks.name=1234-5678=luks-1234 root=/dev/mapper/luks-1234"
    LUKS_UUID="1234-5678"
    LUKS_MAPPER_NAME="luks-1234"

    printf 'UUID=%s / btrfs subvol=/@,defaults,noatime,compress=zstd 0 0\n' "$MOCK_FS_UUID" > "$POST_BOOT_FSTAB"
    printf '%s rootflags=subvol=@ rw quiet splash\n' "$ROOT_SPEC" > "$KERNEL_CMDLINE"

    BTRFS_CALLS=()
    CREATED_SUBVOLS=()
    MKSWAPFILE_SIZES=()
    MKSWAPFILE_PATHS=()
    MOUNT_CALLS=()
    UMOUNT_CALLS=()
    WARN_MSGS=()
    SWAP_DIR_MOUNTED=0
    CURRENT_TOP_MNT=""
    MOCK_MOUNT_TOP_FAIL=0
    MOCK_SUBVOL_FAIL=0
    MOCK_MKSWAPFILE_FAIL=0
}

# ---- 5a. Encrypted Btrfs root + ample free space -> creates @swap, fstab entries,
#          resume=/dev/mapper/... resume_offset=..., no block drop-in.
reset_case "enc-ample"
# Pre-seed drop-in to verify it is actively removed when swapfile setup succeeds.
mkdir -p "$(dirname "$POST_BOOT_NO_HIB_DROPIN")"
printf '[Sleep]\nAllowHibernation=no\n' > "$POST_BOOT_NO_HIB_DROPIN"

_apply_hibernation_policy; rc=$?
chk enc-ample-rc "$rc" "0"
chk enc-ample-subvol-created "${#CREATED_SUBVOLS[@]}" "1"
chk enc-ample-swapfile-size "${MKSWAPFILE_SIZES[0]:-}" "16384m"
chk enc-ample-top-unmounted "$( [[ -z "$CURRENT_TOP_MNT" ]] && echo yes || echo no )" "yes"
chk enc-ample-swap-unmounted "$SWAP_DIR_MOUNTED" "0"
chk enc-ample-return-trap-disarmed "$(trap -p RETURN)" ""
chk enc-ample-fstab-subvol \
    "$(grep -qxF "UUID=${MOCK_FS_UUID} /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk enc-ample-fstab-swapfile \
    "$(grep -qxF '/swap/swapfile none swap defaults,pri=10 0 0' "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk enc-ample-cmdline-resume \
    "$(grep -Eq '(^|[[:space:]])resume=/dev/mapper/luks-1234([[:space:]]|$)' "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk enc-ample-cmdline-offset \
    "$(grep -Eq "(^|[[:space:]])resume_offset=${MOCK_RESUME_OFFSET}([[:space:]]|\$)" "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk enc-ample-no-block-dropin \
    "$( [[ ! -e "$POST_BOOT_NO_HIB_DROPIN" ]] && echo yes || echo no )" "yes"

# ---- 5b. Encrypted Btrfs root + foreign unencrypted GPT swap partition ->
#          marks foreign swap noauto AND still creates encrypted @swap/swapfile.
reset_case "enc-foreign-swap"
MOCK_GPT_SWAPS="/dev/nvme0n1p3 0657fd6d-a4ab-43c4-84e5-0933c84b4f4f 0x0"

_apply_hibernation_policy; rc=$?
chk enc-foreign-rc "$rc" "0"
chk enc-foreign-noauto-written \
    "$(grep -qxF "PARTUUID=${MOCK_SWAP_PARTUUID} none swap noauto 0 0" "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk enc-foreign-fstab-subvol \
    "$(grep -qxF "UUID=${MOCK_FS_UUID} /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk enc-foreign-fstab-swapfile \
    "$(grep -qxF '/swap/swapfile none swap defaults,pri=10 0 0' "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk enc-foreign-cmdline-resume \
    "$(grep -Eq '(^|[[:space:]])resume=/dev/mapper/luks-1234([[:space:]]|$)' "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk enc-foreign-cmdline-offset \
    "$(grep -Eq "(^|[[:space:]])resume_offset=${MOCK_RESUME_OFFSET}([[:space:]]|\$)" "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk enc-foreign-no-block-dropin \
    "$( [[ ! -e "$POST_BOOT_NO_HIB_DROPIN" ]] && echo yes || echo no )" "yes"

# ---- 5c. Encrypted Btrfs root + low disk space (< RAM + 16 GiB) ->
#          skips swapfile and calls _block_hibernation.
reset_case "enc-low-space"
# 16384 MiB RAM + 16384 MiB headroom = 32768 MiB required; provide 32000 MiB.
MOCK_AVAIL_MIB=32000

_apply_hibernation_policy; rc=$?
chk enc-low-rc "$rc" "0"
chk enc-low-no-btrfs-calls "${#BTRFS_CALLS[@]}" "0"
chk enc-low-no-mount-calls "${#MOUNT_CALLS[@]}" "0"
chk enc-low-no-fstab-swap \
    "$(grep -q '/swap' "$POST_BOOT_FSTAB" && echo yes || echo no)" "no"
chk enc-low-no-cmdline-resume \
    "$(grep -q 'resume=' "$KERNEL_CMDLINE" && echo yes || echo no)" "no"
chk enc-low-block-dropin-written \
    "$( [[ -f "$POST_BOOT_NO_HIB_DROPIN" ]] && grep -qxF 'AllowHibernation=no' "$POST_BOOT_NO_HIB_DROPIN" && echo yes || echo no )" "yes"

# ---- 5d. Plaintext Btrfs root + ample space ->
#          creates @swap/swapfile with resume=UUID=... resume_offset=...
reset_case "plain-btrfs"
ROOT_PART_DEV="/dev/nvme0n1p2"
ROOT_SPEC="root=PARTUUID=22222222-3333-4444-5555-666666666666"
LUKS_UUID=""
LUKS_MAPPER_NAME=""
printf '%s rootflags=subvol=@ rw quiet splash\n' "$ROOT_SPEC" > "$KERNEL_CMDLINE"

_apply_hibernation_policy; rc=$?
chk plain-btrfs-rc "$rc" "0"
chk plain-btrfs-subvol-created "${#CREATED_SUBVOLS[@]}" "1"
chk plain-btrfs-fstab-subvol \
    "$(grep -qxF "UUID=${MOCK_FS_UUID} /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk plain-btrfs-fstab-swapfile \
    "$(grep -qxF '/swap/swapfile none swap defaults,pri=10 0 0' "$POST_BOOT_FSTAB" && echo yes || echo no)" "yes"
chk plain-btrfs-cmdline-resume \
    "$(grep -Eq "(^|[[:space:]])resume=UUID=${MOCK_FS_UUID}([[:space:]]|\$)" "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk plain-btrfs-cmdline-offset \
    "$(grep -Eq "(^|[[:space:]])resume_offset=${MOCK_RESUME_OFFSET}([[:space:]]|\$)" "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk plain-btrfs-no-block-dropin \
    "$( [[ ! -e "$POST_BOOT_NO_HIB_DROPIN" ]] && echo yes || echo no )" "yes"

# ---- 5e. Idempotent re-run when resume= is already present OR fstab entries already exist
# Sub-test 1: Re-running _apply_hibernation_policy and _setup_btrfs_swapfile_hibernation
# right after a successful encrypted Btrfs setup (resume= already present).
reset_case "idempotent"
_apply_hibernation_policy; rc=$?
chk idem-first-rc "$rc" "0"

BTRFS_CALLS=()
MOUNT_CALLS=()
_setup_btrfs_swapfile_hibernation; direct_rc=$?
chk idem-direct-skip-when-resume-present "$direct_rc" "1"
chk idem-direct-no-btrfs "${#BTRFS_CALLS[@]}" "0"

_apply_hibernation_policy; second_rc=$?
chk idem-second-rc "$second_rc" "0"
chk idem-second-no-btrfs "${#BTRFS_CALLS[@]}" "0"
chk idem-second-no-block-dropin \
    "$( [[ ! -e "$POST_BOOT_NO_HIB_DROPIN" ]] && echo yes || echo no )" "yes"
chk idem-fstab-subvol-count \
    "$(grep -cxF "UUID=${MOCK_FS_UUID} /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$POST_BOOT_FSTAB")" "1"
chk idem-fstab-swapfile-count \
    "$(grep -cxF '/swap/swapfile none swap defaults,pri=10 0 0' "$POST_BOOT_FSTAB")" "1"

# Sub-test 2: fstab entries and @swap/swapfile already exist, but kernel cmdline
# had resume= stripped/regenerated -> restores resume= without duplicating fstab,
# subvolume creation, or mkswapfile.
printf '%s rootflags=subvol=@ rw quiet splash\n' "$ROOT_SPEC" > "$KERNEL_CMDLINE"
CREATED_SUBVOLS=()
MKSWAPFILE_SIZES=()
_apply_hibernation_policy; third_rc=$?
chk idem-third-rc "$third_rc" "0"
chk idem-third-no-subvol-recreate "${#CREATED_SUBVOLS[@]}" "0"
chk idem-third-no-mkswapfile-recreate "${#MKSWAPFILE_SIZES[@]}" "0"
chk idem-third-fstab-subvol-count \
    "$(grep -cxF "UUID=${MOCK_FS_UUID} /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$POST_BOOT_FSTAB")" "1"
chk idem-third-fstab-swapfile-count \
    "$(grep -cxF '/swap/swapfile none swap defaults,pri=10 0 0' "$POST_BOOT_FSTAB")" "1"
chk idem-third-cmdline-resume \
    "$(grep -Eq '(^|[[:space:]])resume=/dev/mapper/luks-1234([[:space:]]|$)' "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk idem-third-cmdline-offset \
    "$(grep -Eq "(^|[[:space:]])resume_offset=${MOCK_RESUME_OFFSET}([[:space:]]|\$)" "$KERNEL_CMDLINE" && echo yes || echo no)" "yes"
chk idem-third-swap-unmounted "$SWAP_DIR_MOUNTED" "0"

# ---- 5f. Cleanup & RETURN-trap disarmament on early error returns
# Sub-test 1: subvolid=5 mount fails -> top_mnt removed, RETURN trap disarmed.
reset_case "err-top-mount"
MOCK_MOUNT_TOP_FAIL=1
_setup_btrfs_swapfile_hibernation; rc=$?
chk err-top-mount-rc "$rc" "1"
chk err-top-mount-return-trap-disarmed "$(trap -p RETURN)" ""
chk err-top-mount-no-leaked-tmpdir \
    "$(compgen -G "$TMPDIR/mainstream-btrfs-top.*" >/dev/null 2>&1 && echo yes || echo no)" "no"
# Verify subsequent function calls do not trigger any lingering RETURN trap.
UMOUNT_CALLS=()
_dummy_after_err() { return 0; }
_dummy_after_err
chk err-top-mount-no-lingering-trap-umount "${#UMOUNT_CALLS[@]}" "0"

# Sub-test 2: btrfs subvolume create fails -> top_mnt unmounted & removed, trap disarmed.
reset_case "err-subvol-create"
MOCK_SUBVOL_FAIL=1
_setup_btrfs_swapfile_hibernation; rc=$?
chk err-subvol-create-rc "$rc" "1"
chk err-subvol-create-top-unmounted "$( [[ -z "$CURRENT_TOP_MNT" ]] && echo yes || echo no )" "yes"
chk err-subvol-create-return-trap-disarmed "$(trap -p RETURN)" ""
chk err-subvol-create-no-leaked-tmpdir \
    "$(compgen -G "$TMPDIR/mainstream-btrfs-top.*" >/dev/null 2>&1 && echo yes || echo no)" "no"

# Sub-test 3: mkswapfile fails AFTER mounting $swap_dir -> partial file deleted,
# $swap_dir cleanly unmounted, fstab untouched, RETURN trap disarmed.
reset_case "err-mkswapfile"
MOCK_MKSWAPFILE_FAIL=1
_setup_btrfs_swapfile_hibernation; rc=$?
chk err-mkswapfile-rc "$rc" "1"
chk err-mkswapfile-swap-unmounted "$SWAP_DIR_MOUNTED" "0"
chk err-mkswapfile-return-trap-disarmed "$(trap -p RETURN)" ""
chk err-mkswapfile-no-partial-file \
    "$( [[ ! -e "$POST_BOOT_SWAP_DIR/swapfile" ]] && echo yes || echo no )" "yes"
chk err-mkswapfile-fstab-clean \
    "$(grep -q '/swap' "$POST_BOOT_FSTAB" && echo yes || echo no)" "no"

# Sub-test 4: invalid resume_offset (0) AFTER mounting $swap_dir ->
# $swap_dir cleanly unmounted, fstab untouched, RETURN trap disarmed.
reset_case "err-bad-offset"
MOCK_RESUME_OFFSET="0"
_setup_btrfs_swapfile_hibernation; rc=$?
chk err-bad-offset-rc "$rc" "1"
chk err-bad-offset-swap-unmounted "$SWAP_DIR_MOUNTED" "0"
chk err-bad-offset-return-trap-disarmed "$(trap -p RETURN)" ""
chk err-bad-offset-fstab-clean \
    "$(grep -q '/swap' "$POST_BOOT_FSTAB" && echo yes || echo no)" "no"

# Sub-test 5: Pre-existing mount at $swap_dir is NOT unmounted by cleanup.
reset_case "premounted-swap"
SWAP_DIR_MOUNTED=1
mkdir -p "$POST_BOOT_SWAP_DIR"
_setup_btrfs_swapfile_hibernation; rc=$?
chk premounted-swap-rc "$rc" "0"
chk premounted-swap-stays-mounted "$SWAP_DIR_MOUNTED" "1"
chk premounted-swap-return-trap-disarmed "$(trap -p RETURN)" ""

if [[ $FAILS -eq 0 ]]; then
    echo "post-install-security: all $N assertions PASS"
else
    echo "post-install-security: $FAILS of $N FAILED"
fi
exit $FAILS
