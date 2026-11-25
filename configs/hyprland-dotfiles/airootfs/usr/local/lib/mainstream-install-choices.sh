#!/usr/bin/env bash
# The kernel, app source and Proton picked in the app list, which the
# installchoices step writes before the boot loader step.

MAINSTREAM_CHOICES_FILE="${MAINSTREAM_CHOICES_FILE:-/etc/mainstream-install/choices.conf}"
MAINSTREAM_CPUINFO="${MAINSTREAM_CPUINFO:-/proc/cpuinfo}"

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
            [[ "$word" == "$allowed" ]] && { out+=("$allowed"); break; }
        done
    done
    printf '%s\n' "${out[*]}"
}

# chosen_kernels: the kernels to install, the preferred boot default first.
# Without the choices file that is today's pair. The performance kernel turns
# into Mainstream's on a CPU that cannot start it, since such a machine would
# not boot, and an empty choice means Mainstream's.
chosen_kernels() {
    local k out=() seen=" "
    for k in $(install_choice_list KERNELS "linux-mainstream linux" \
            linux-mainstream-performance linux-mainstream linux); do
        [[ "$k" == linux-mainstream-performance ]] && ! cpu_runs_x86_64_v3 && k=linux-mainstream
        [[ "$seen" == *" $k "* ]] && continue
        seen+="$k "
        out+=("$k")
    done
    (( ${#out[@]} )) || out=(linux-mainstream)
    printf '%s\n' "${out[*]}"
}

# chosen_protons: the Protons to install, Steam's default first; Proton
# Mainstream without the choices file.
chosen_protons() {
    install_choice_list PROTONS mainstream mainstream ge cachyos
}

# The installed system's own kernel: the edition's (Arch's linux, or linux-t2 on
# the MacBook edition) when it is installed, otherwise the Mainstream kernel that
# replaced it. pkgbase is what pacman recorded; uname would name the live kernel.
installed_edition_kernel() {
    local d own="" mainstream=""
    for d in "${MAINSTREAM_MODULES_DIR:-/usr/lib/modules}"/*/; do
        [[ -r "$d/pkgbase" ]] || continue
        if [[ "$(<"$d/pkgbase")" == linux-mainstream* ]]; then
            mainstream+="$(basename "$d") $(<"$d/pkgbase")"$'\n'
        else
            own+="$(basename "$d") $(<"$d/pkgbase")"$'\n'
        fi
    done
    [[ -n "$own" ]] || own="$mainstream"
    own=$(printf '%s' "$own" | sort -V | tail -n1 | cut -d' ' -f2)
    printf '%s\n' "${own:-linux}"
}
