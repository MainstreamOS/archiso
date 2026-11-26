#!/usr/bin/env bash
# Follow the kernel choice from the app list through every install step with fakes:
# only Custom adds or swaps kernels, everything else installs Mainstream's alone.
set -uo pipefail
ARCHISO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIROOTFS="$ARCHISO_ROOT/configs/hyprland-dotfiles/airootfs"
CHOICES_PY="$AIROOTFS/etc/calamares/modules/installchoices/main.py"
CHOICES_LIB="$AIROOTFS/usr/local/lib/mainstream-install-choices.sh"
INSTALL_LIMINE="$AIROOTFS/usr/local/bin/install-limine"
POST_BOOT="$AIROOTFS/usr/local/bin/post-install-boot"
FINALIZE="$AIROOTFS/usr/local/bin/finalize-install"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0; N=0
info() { :; }; warn() { WARN+=("$*"); }
chk() { N=$((N+1)); [[ "$2" == "$3" ]] || { echo "  FAIL [$1] got '$2' want '$3'"; FAILS=$((FAILS+1)); }; }

# A target root whose usr/lib/modules holds one tree per "release:package".
mkroot() {
    local root="$1" r
    shift
    mkdir -p "$root/usr/lib/modules"
    for r in "$@"; do
        mkdir -p "$root/usr/lib/modules/${r%%:*}"
        echo "${r#*:}" > "$root/usr/lib/modules/${r%%:*}/pkgbase"
    done
}
mkroot "$TMP/root-mainstream" 7.3.6-1-mainstream:linux-mainstream
mkroot "$TMP/root-empty"
mkroot "$TMP/root-both" 7.3.6-1-mainstream:linux-mainstream 6.18.1-arch1-1:linux

# ---- 1. installchoices: the kernels each method records, and what it downloads
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nshift\necho "$*" >> "%s"\n' "$TMP/fetch.log" > "$TMP/bin/fetch-online"
chmod +x "$TMP/bin/fetch-online"
cat > "$TMP/drive.py" <<'PY'
import importlib.util, os, sys, types

lc = types.ModuleType("libcalamares")
lc.utils = types.SimpleNamespace(debug=lambda *a: None, warning=lambda *a: None)
sys.modules["libcalamares"] = lc
spec = importlib.util.spec_from_file_location("installchoices", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class GlobalStorage:
    def __init__(self, values):
        self.values = values

    def value(self, key):
        return self.values.get(key)

    def insert(self, key, value):
        self.values[key] = value


cmd, args = sys.argv[2], sys.argv[3:]
if cmd == "resolve":
    method, v3, items = args[0], args[1] == "1", set(args[2:])
    print(" ".join(m.resolve(method, items, v3)[1]))
elif cmd == "freemib":
    print(m.boot_free_mib(args[0]))
elif cmd == "run":
    method, v3, root, fetch, items = args[0], args[1] == "1", args[2], args[3], args[4:]
    m.cpu_runs_x86_64_v3 = lambda: v3
    m.FETCH_ONLINE = fetch
    m.PCI_DEVICES = os.environ["PCI_DEVICES"]
    if os.environ.get("BOOT_FREE_MIB"):
        m.boot_free_mib = lambda root: int(os.environ["BOOT_FREE_MIB"])
    lc.globalstorage = GlobalStorage({
        "installmethod_choice": method,
        "rootMountPoint": root,
        "packageOperations": [{"install": items}],
    })
    if m.run() is not None:
        print("error")
    with open(os.path.join(root, m.CHOICES_FILE.lstrip("/"))) as f:
        print([l.split("=", 1)[1].strip() for l in f if l.startswith("KERNELS=")][0])
PY
choices() { python3 -I -B "$TMP/drive.py" "$CHOICES_PY" "$@"; }
# The display devices the installer sees: none of this machine's own.
pcidev() {  # pcidev <dir> <slot> <vendor> <class>
    mkdir -p "$1/$2"; echo "$3" > "$1/$2/vendor"; echo "$4" > "$1/$2/class"
}
export PCI_DEVICES="$TMP/pci-none"; mkdir -p "$PCI_DEVICES"
pcidev "$TMP/pci-nvidia" 0000:00:02.0 0x8086 0x030000
pcidev "$TMP/pci-nvidia" 0000:01:00.0 0x10de 0x030200
pcidev "$TMP/pci-intel" 0000:00:02.0 0x8086 0x030000
pcidev "$TMP/pci-intel" 0000:00:1f.3 0x10de 0x040300

for method in default console os-only developer gaming; do
    chk "resolve-$method" "$(choices resolve "$method" 1 kernel:linux kernel:linux-mainstream-performance)" "linux-mainstream"
done
chk resolve-custom-perf "$(choices resolve custom 1 kernel:linux-mainstream-performance)" "linux-mainstream-performance"
chk resolve-custom-perf-no-v3 "$(choices resolve custom 0 kernel:linux-mainstream-performance)" "linux-mainstream"
chk resolve-custom-m-a "$(choices resolve custom 1 kernel:linux kernel:linux-mainstream)" "linux-mainstream linux"
chk resolve-custom-all "$(choices resolve custom 1 kernel:linux kernel:linux-mainstream kernel:linux-mainstream-performance)" \
    "linux-mainstream-performance linux-mainstream linux"
chk resolve-custom-none "$(choices resolve custom 1 apps:flatpak)" "linux-mainstream"

: > "$TMP/fetch.log"
chk run-default-kernels "$(choices run default 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" kernel:linux)" "linux-mainstream"
chk run-unknown-method "$(choices run bogus 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" kernel:linux)" "linux-mainstream"
chk run-default-no-fetch "$(cat "$TMP/fetch.log")" ""
# Only the Mainstream kernels the target lacks: Arch's comes from core in
# install-limine, and the image's own is already there.
chk run-custom-kernels "$(choices run custom 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" \
    kernel:linux kernel:linux-mainstream kernel:linux-mainstream-performance)" \
    "linux-mainstream-performance linux-mainstream linux"
chk run-custom-fetch "$(cat "$TMP/fetch.log")" "--kernel linux-mainstream-performance"
# install-limine leaves out a kernel the boot partition has no room for, so it is not fetched.
: > "$TMP/fetch.log"
BOOT_FREE_MIB=300 choices run custom 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" kernel:linux-mainstream-performance >/dev/null
chk run-small-esp-no-fetch "$(cat "$TMP/fetch.log")" ""
BOOT_FREE_MIB=600 choices run custom 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" kernel:linux-mainstream-performance >/dev/null
chk run-roomy-esp-fetch "$(cat "$TMP/fetch.log")" "--kernel linux-mainstream-performance"
mkdir -p "$TMP/root-mainstream/boot"
chk boot-free-mib-reads "$(choices freemib "$TMP/root-mainstream" | grep -cE '^[0-9]+$')" "1"
: > "$TMP/fetch.log"
chk run-empty-target-kernels "$(choices run custom 1 "$TMP/root-empty" "$TMP/bin/fetch-online" kernel:linux-mainstream-performance)" \
    "linux-mainstream-performance"
chk run-empty-target-fetch "$(cat "$TMP/fetch.log")" "--kernel linux-mainstream-performance"
# An NVIDIA display device: fetch-online decides whether its driver is needed,
# with the chosen kernels or on its own. A non-display NVIDIA function is not one.
: > "$TMP/fetch.log"
PCI_DEVICES="$TMP/pci-nvidia" choices run default 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" >/dev/null
chk run-nvidia-fetch "$(cat "$TMP/fetch.log")" "--nvidia"
: > "$TMP/fetch.log"
PCI_DEVICES="$TMP/pci-nvidia" choices run custom 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" kernel:linux-mainstream-performance >/dev/null
chk run-nvidia-kernel-fetch "$(cat "$TMP/fetch.log")" "--kernel linux-mainstream-performance --nvidia"
: > "$TMP/fetch.log"
PCI_DEVICES="$TMP/pci-intel" choices run default 1 "$TMP/root-mainstream" "$TMP/bin/fetch-online" >/dev/null
chk run-no-nvidia-no-fetch "$(cat "$TMP/fetch.log")" ""

# ---- 2. the shared choices library the install steps read
# shellcheck source=/dev/null
source "$CHOICES_LIB"
printf 'flags\t\t: fpu sse2 avx avx2 bmi1 bmi2 f16c fma movbe xsave abm\n' > "$TMP/cpuinfo-v3"
printf 'flags\t\t: fpu sse2 avx\n' > "$TMP/cpuinfo-v2"
MAINSTREAM_CPUINFO="$TMP/cpuinfo-v3"
printf '00:02.0 0300: 8086:3e9b\n' > "$TMP/lspci-plain"
printf '00:02.0 0300: 8086:3e9b\n02:00.1 0880: 106b:1801 (rev 01)\n' > "$TMP/lspci-t2"
MAINSTREAM_LSPCI_N="$TMP/lspci-plain"
MAINSTREAM_CHOICES_FILE="$TMP/missing/choices.conf"
chk chosen-no-file "$(chosen_kernels)" "linux-mainstream"
MAINSTREAM_CHOICES_FILE="$TMP/choices.conf"
printf 'KERNELS=\n' > "$MAINSTREAM_CHOICES_FILE"
chk chosen-empty "$(chosen_kernels)" "linux-mainstream"
printf 'KERNELS=linux linux-mainstream\n' > "$MAINSTREAM_CHOICES_FILE"
chk chosen-m-a "$(chosen_kernels)" "linux-mainstream linux"
printf 'KERNELS=linux-mainstream-performance linux-mainstream\n' > "$MAINSTREAM_CHOICES_FILE"
chk chosen-perf-v3 "$(chosen_kernels)" "linux-mainstream-performance linux-mainstream"
MAINSTREAM_CPUINFO="$TMP/cpuinfo-v2"
chk chosen-perf-no-v3 "$(chosen_kernels)" "linux-mainstream"
MAINSTREAM_CPUINFO="$TMP/cpuinfo-v3"
# Arch's kernel has no T2 drivers, so a T2 Mac keeps Mainstream's as its default.
printf 'KERNELS=linux\n' > "$MAINSTREAM_CHOICES_FILE"
chk chosen-arch-only "$(chosen_kernels)" "linux"
MAINSTREAM_LSPCI_N="$TMP/lspci-t2"
chk chosen-t2-arch-only "$(chosen_kernels)" "linux-mainstream linux"
printf 'KERNELS=linux-mainstream-performance linux\n' > "$MAINSTREAM_CHOICES_FILE"
chk chosen-t2-perf-kept "$(chosen_kernels)" "linux-mainstream-performance linux"
MAINSTREAM_LSPCI_N="$TMP/lspci-plain"

chk edition-lib-none "$(MAINSTREAM_MODULES_DIR="$TMP/missing" installed_edition_kernel)" "linux-mainstream"
chk edition-lib-mainstream "$(MAINSTREAM_MODULES_DIR="$TMP/root-mainstream/usr/lib/modules" installed_edition_kernel)" "linux-mainstream"
chk edition-lib-arch "$(MAINSTREAM_MODULES_DIR="$TMP/root-both/usr/lib/modules" installed_edition_kernel)" "linux"

# Fake pacman for the steps below: INSTALLED and REPO are word lists, -Qq answers
# by exact name, and the Mainstream kernels' headers answer for linux-headers.
pacman() {
    local p
    case "$1" in
        -Qq)
            for p in $INSTALLED; do [[ $p == "$2" ]] && { echo "$p"; return 0; }; done
            [[ $2 == linux-headers && " $INSTALLED " == *" linux-mainstream-headers "* ]] \
                && { echo linux-mainstream-headers; return 0; }
            return 1 ;;
        -Si) [[ " $REPO " == *" $2 "* ]] ;;
        *) PAC+=("$*") ;;
    esac
}

# ---- 3. install-limine adds the other chosen kernels beside the image's
eval "$(awk '/^install_chosen_kernels\(\) \{/,/^\}/' "$INSTALL_LIMINE")"
timeout() { shift 5; "$@"; }
df() { printf 'Filesystem 1048576-blocks Used Available Capacity Mounted on\n/dev/x 4096 0 %s 0%% /boot\n' "$FREE"; }
BOOT_PATH=/boot; KERNEL_MIN_FREE_MIB=512; FREE=2048
KERNEL_PKG=linux-mainstream
INSTALLED="linux-mainstream linux-mainstream-headers"
REPO="linux-mainstream-performance linux-mainstream-performance-headers"

CHOSEN_KERNELS=(linux-mainstream); PAC=(); WARN=()
install_chosen_kernels
chk limine-default "${PAC[*]:-none}" "none"
CHOSEN_KERNELS=(linux-mainstream linux); PAC=(); WARN=()
install_chosen_kernels
chk limine-arch-offline "${PAC[*]:-none}" "none"
chk limine-arch-offline-warns "$( [[ "${WARN[*]}" == *"needs a connection"*"linux-mainstream stays"* ]] && echo yes || echo no )" "yes"
REPO="$REPO linux linux-headers"; PAC=(); WARN=()
install_chosen_kernels
chk limine-arch-online "${PAC[*]:-none}" "-S --needed --noconfirm linux linux-headers"
CHOSEN_KERNELS=(linux-mainstream-performance); PAC=()
install_chosen_kernels
chk limine-perf "${PAC[*]:-none}" "-S --needed --noconfirm linux-mainstream-performance linux-mainstream-performance-headers"
FREE=300; PAC=()
install_chosen_kernels
chk limine-perf-no-room "${PAC[*]:-none}" "none"
FREE=2048

# ---- 4. post-install-boot keeps only the chosen kernels, and the boot menu only theirs
eval "pick_kernels() {
$(awk '/^CHOSEN_KERNEL=""$/,/^fi$/' "$POST_BOOT")
}"
NOT_READY=""
gpu_kernel_nvidia_ready() { [[ " $NOT_READY " != *" $1 "* ]]; }

CHOSEN_KERNELS=(linux-mainstream); INSTALLED="linux-mainstream linux-mainstream-headers"; PAC=()
pick_kernels
chk boot-default "$CHOSEN_KERNEL ${PAC[*]:-none}" "linux-mainstream none"
CHOSEN_KERNELS=(linux-mainstream-performance)
INSTALLED="linux-mainstream linux-mainstream-headers linux-mainstream-performance linux-mainstream-performance-headers"; PAC=()
pick_kernels
chk boot-perf "$CHOSEN_KERNEL" "linux-mainstream-performance"
chk boot-perf-drops-image "${PAC[*]:-none}" "-R --noconfirm linux-mainstream linux-mainstream-headers"
CHOSEN_KERNELS=(linux-mainstream linux); INSTALLED="linux-mainstream linux-mainstream-headers linux linux-headers"; PAC=()
pick_kernels
chk boot-m-a "$CHOSEN_KERNEL ${PAC[*]:-none}" "linux-mainstream none"
CHOSEN_KERNELS=(linux); PAC=()
pick_kernels
chk boot-arch "$CHOSEN_KERNEL" "linux"
chk boot-arch-drops-image "${PAC[*]:-none}" "-R --noconfirm linux-mainstream linux-mainstream-headers"
# Arch's kernel could not be installed: nothing is chosen, so the image's stays.
INSTALLED="linux-mainstream linux-mainstream-headers"; PAC=()
pick_kernels
chk boot-arch-missing "${CHOSEN_KERNEL:-none} ${PAC[*]:-none}" "none none"
# A chosen kernel without the NVIDIA module another one has is not made the default.
CHOSEN_KERNELS=(linux-mainstream-performance)
INSTALLED="linux-mainstream linux-mainstream-headers linux-mainstream-performance linux-mainstream-performance-headers"
NOT_READY="linux-mainstream-performance"; PAC=()
pick_kernels
chk boot-not-ready "${CHOSEN_KERNEL:-none} ${PAC[*]:-none}" "none none"
NOT_READY=""

eval "$(awk '/^_limine_drop_entry\(\) \{/,/^\}/' "$POST_BOOT")"
eval "drop_gone_entries() {
$(awk '/^# install-limine named its placeholder/,/^done$/' "$POST_BOOT")
}"
BOOT_PATH="$TMP/esp"; mkdir -p "$BOOT_PATH"
write_conf() {
    cat > "$BOOT_PATH/limine.conf" <<'CONF'
timeout: 5
/+Mainstream OS\\
comment: Mainstream OS\\
    //linux-mainstream-performance
        protocol: efi
        path: boot():///EFI/Linux/mainstream_linux-mainstream-performance.efi
    //linux-mainstream
        protocol: linux
        kernel_path: boot():///vmlinuz-linux-mainstream
    //Snapshots
/Windows
    //linux-mainstream
        protocol: efi
CONF
}
# The GPU step removed the image's kernel: its placeholder goes, the rest stays.
write_conf; INSTALLED="linux-mainstream-performance linux-mainstream-performance-headers"
drop_gone_entries
ours() { sed -n '/^\/+Mainstream OS/,/^\/Windows/p' "$BOOT_PATH/limine.conf"; }
chk menu-drops-gone "$(ours | grep -c '//linux-mainstream$')" "0"
chk menu-drops-whole-entry "$(ours | grep -c 'vmlinuz-linux-mainstream')" "0"
chk menu-keeps-other-os "$(sed -n '/^\/Windows/,$p' "$BOOT_PATH/limine.conf" | grep -c '//linux-mainstream$')" "1"
chk menu-keeps-installed "$(grep -c '//linux-mainstream-performance$' "$BOOT_PATH/limine.conf")" "1"
chk menu-keeps-snapshots "$(grep -c '//Snapshots$' "$BOOT_PATH/limine.conf")" "1"
write_conf; INSTALLED="linux-mainstream linux-mainstream-performance"
drop_gone_entries
chk menu-keeps-all "$(ours | grep -c '//linux-mainstream')" "2"

# ---- 5. finalize-install keeps Arch's headers while Arch's kernel is there
eval "prune_headers() {
$(awk '/^# Arch.s headers stay with Arch.s kernel/,/^fi$/' "$FINALIZE")
}"
remove_pkgs() { REMOVED+=("$@"); }
# Nothing registered with DKMS, as on a machine without an NVIDIA card.
dkms() { :; }
INSTALLED="linux-mainstream linux-mainstream-headers linux linux-headers"; REMOVED=()
prune_headers
chk headers-arch-kept "${REMOVED[*]:-none}" "none"
INSTALLED="linux-mainstream linux-mainstream-headers linux-headers"; REMOVED=()
prune_headers
chk headers-orphan-removed "${REMOVED[*]:-none}" "linux-headers"
INSTALLED="linux-mainstream linux-mainstream-headers"; REMOVED=()
prune_headers
chk headers-provider-kept "${REMOVED[*]:-none}" "none"

# ---- 6. finalize-install removes packages by their exact names
# On the legacy edition nvidia-580xx-utils provides nvidia-utils, and naming that in
# one batch made pacman refuse the whole removal.
eval "$(awk '/^_pkg_installed\(\) \{/,/^\}/' "$FINALIZE")"
eval "$(awk '/^remove_pkgs\(\) \{/,/^\}/' "$FINALIZE")"
pacman() {
    case "$1" in
        -Qq)
            [[ " $INSTALLED " == *" $2 "* ]] && { echo "$2"; return 0; }
            [[ $2 == nvidia-utils && " $INSTALLED " == *" nvidia-580xx-utils "* ]] && { echo nvidia-580xx-utils; return 0; }
            return 1 ;;
        -Rns) shift; echo "$*" >> "$TMP/rns.log" ;;
    esac
}
INSTALLED="nvidia-580xx-dkms nvidia-580xx-utils"; WARN=()
remove_pkgs nvidia-utils nvidia-580xx-dkms nvidia-580xx-utils >/dev/null
chk remove-exact-names "$(cat "$TMP/rns.log")" "--noconfirm nvidia-580xx-dkms nvidia-580xx-utils"
chk remove-no-warning "${#WARN[@]}" "0"

[[ $FAILS -eq 0 ]] && echo "install-kernels: all $N assertions PASS" || echo "install-kernels: $FAILS of $N FAILED"
exit $FAILS
