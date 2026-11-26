#!/usr/bin/env bash
# Mainstream's kernel names, and the kernel, app source and Proton picked in the
# app list, which the installchoices step writes before the boot loader step.

MAINSTREAM_CHOICES_FILE="${MAINSTREAM_CHOICES_FILE:-/etc/mainstream-install/choices.conf}"
MAINSTREAM_CPUINFO="${MAINSTREAM_CPUINFO:-/proc/cpuinfo}"

# Mainstream's kernel packages, the performance one first. Named by these lists,
# never by a pattern: mainstream* also matches mainstream-system and the rest.
MAINSTREAM_DEFAULT_KERNEL=mainstream
MAINSTREAM_PERFORMANCE_KERNEL=mainstream-performance
MAINSTREAM_KERNEL_PACKAGES=("$MAINSTREAM_PERFORMANCE_KERNEL" "$MAINSTREAM_DEFAULT_KERNEL" mainstream-performance-eac)
# The kernels the installer offers, in order of preference.
INSTALLER_KERNELS=("$MAINSTREAM_PERFORMANCE_KERNEL" "$MAINSTREAM_DEFAULT_KERNEL" linux)

# mainstream_kernel_name NAME: the package name of a kernel, also when it is named
# with the linux- prefix a choices file or an older image may still use.
mainstream_kernel_name() {
    case "$1" in
        linux-mainstream|linux-mainstream-performance|linux-mainstream-performance-eac)
            printf '%s\n' "${1#linux-}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# is_mainstream_kernel NAME: one of Mainstream's kernels, by either name.
is_mainstream_kernel() {
    local k name
    name="$(mainstream_kernel_name "$1")"
    for k in "${MAINSTREAM_KERNEL_PACKAGES[@]}"; do
        [[ "$name" == "$k" ]] && return 0
    done
    return 1
}

# install_choice KEY DEFAULT ALLOWED...: the stored value when it is one of
# ALLOWED, otherwise DEFAULT. Parsed rather than sourced: the file names packages.
install_choice() {
    local key="$1" def="$2" val="" allowed
    shift 2
    if [[ -r "$MAINSTREAM_CHOICES_FILE" ]]; then
        val=$(sed -n "s/^${key}=//p" "$MAINSTREAM_CHOICES_FILE" | tail -n1)
    fi
    for allowed in "$@"; do
        [[ "$val" == "$allowed" ]] && { printf '%s\n' "$val"; return 0; }
    done
    printf '%s\n' "$def"
}

# The performance kernel and Proton CachyOS's faster build need x86-64-v3; the
# same test as mainstream-kernels.
cpu_runs_x86_64_v3() {
    local line flags="" flag
    [[ -r "$MAINSTREAM_CPUINFO" ]] || return 1
    while IFS= read -r line; do
        if [[ $line == flags* ]]; then
            flags=" ${line#*:} "
            break
        fi
    done < "$MAINSTREAM_CPUINFO"
    for flag in avx avx2 bmi1 bmi2 f16c fma movbe xsave; do
        [[ $flags == *" $flag "* ]] || return 1
    done
    [[ $flags == *" abm "* || $flags == *" lzcnt "* ]]
}

# install_choice_list KEY DEFAULT ALLOWED...: the stored list (space separated)
# with unknown words dropped, in the order of ALLOWED; DEFAULT when the file has no
# such line. A present but empty line is an empty list.
install_choice_list() {
    local key="$1" def="$2" line allowed word out=()
    shift 2
    if [[ ! -r "$MAINSTREAM_CHOICES_FILE" ]] || ! grep -q "^${key}=" "$MAINSTREAM_CHOICES_FILE"; then
        printf '%s\n' "$def"
        return 0
    fi
    line=" $(sed -n "s/^${key}=//p" "$MAINSTREAM_CHOICES_FILE" | tail -n1) "
    for allowed in "$@"; do
        for word in $line; do
            [[ "$key" == KERNELS ]] && word="$(mainstream_kernel_name "$word")"
            [[ "$word" == "$allowed" ]] && { out+=("$allowed"); break; }
        done
    done
    printf '%s\n' "${out[*]}"
}

# machine_has_t2: an Apple T2 chip (106b:1801/1802), whose keyboard and trackpad
# only Mainstream's kernels drive.
machine_has_t2() {
    if [[ -n "${MAINSTREAM_LSPCI_N:-}" ]]; then cat "$MAINSTREAM_LSPCI_N"; else lspci -n 2>/dev/null; fi \
        | grep -qE ' 106b:180[12]( |$)'
}

# chosen_kernels: the kernels to install, the preferred boot default first.
# Without the choices file that is Mainstream's, which the image carries. The
# performance kernel turns into Mainstream's on a CPU that cannot start it,
# since such a machine would not boot, and an empty choice means Mainstream's.
# A T2 Mac keeps Mainstream's as its default even when only Arch's was chosen.
chosen_kernels() {
    local k out=() seen=" " own=false
    for k in $(install_choice_list KERNELS "$MAINSTREAM_DEFAULT_KERNEL" "${INSTALLER_KERNELS[@]}"); do
        [[ "$k" == "$MAINSTREAM_PERFORMANCE_KERNEL" ]] && ! cpu_runs_x86_64_v3 && k=$MAINSTREAM_DEFAULT_KERNEL
        [[ "$seen" == *" $k "* ]] && continue
        seen+="$k "
        out+=("$k")
        is_mainstream_kernel "$k" && own=true
    done
    (( ${#out[@]} )) || { out=("$MAINSTREAM_DEFAULT_KERNEL"); own=true; }
    if [[ $own != true ]] && machine_has_t2; then
        out=("$MAINSTREAM_DEFAULT_KERNEL" "${out[@]}")
    fi
    printf '%s\n' "${out[*]}"
}

# chosen_protons: the Protons to install, Steam's default first; Proton
# Mainstream without the choices file.
chosen_protons() {
    install_choice_list PROTONS mainstream mainstream ge cachyos
}

# The installed system's own kernel, which names its preset: Arch's linux when
# it is installed, otherwise the newest Mainstream kernel. pkgbase is what pacman
# recorded; uname would name the live kernel.
installed_edition_kernel() {
    local d base own="" mainstream=""
    for d in "${MAINSTREAM_MODULES_DIR:-/usr/lib/modules}"/*/; do
        [[ -r "$d/pkgbase" ]] || continue
        base="$(<"$d/pkgbase")"
        if is_mainstream_kernel "$base"; then
            mainstream+="$(basename "$d") $base"$'\n'
        else
            own+="$(basename "$d") $base"$'\n'
        fi
    done
    [[ -n "$own" ]] || own="$mainstream"
    own=$(printf '%s' "$own" | sort -V | tail -n1 | cut -d' ' -f2)
    printf '%s\n' "${own:-$MAINSTREAM_DEFAULT_KERNEL}"
}
