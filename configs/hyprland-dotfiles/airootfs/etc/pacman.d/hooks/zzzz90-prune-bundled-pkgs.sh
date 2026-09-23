# remove from airootfs!
# Run by zzzz90-prune-bundled-pkgs.hook while the ISO is built. It sits in the
# hooks directory so the zzzz99 hook removes it with the other build-only files.
set -uo pipefail

dir=/usr/local/share/pkgs
db="$dir/mainstream.db.tar.gz"
[[ -d "$dir" ]] || exit 0

# The wl set is built against Arch's kernel. On an image that ships another
# one (linux-t2 on the MacBook edition), post-install-boot takes the whole set
# from the repositories instead, so the staged copy would never be used.
# By name: linux-t2 provides linux, and pacman -Q answers with a provider.
wl_unused=false
if [[ "$(pacman -Qq linux 2>/dev/null)" == linux ]]; then
    # DKMS builds the driver against the staged headers, so headers for any
    # other kernel would give a Mac a driver for a kernel it does not run.
    kver=$(pacman -Q linux 2>/dev/null | awk '{print $2}')
    for f in "$dir"/linux-headers-[0-9]*.pkg.tar.zst; do
        [[ -f "$f" ]] || continue
        read -r _ hver < <(pacman -Qp "$f" 2>/dev/null) || hver=""
        if [[ "$hver" != "$kver" ]]; then
            echo "Staged linux-headers ${hver:-?} does not match the live kernel $kver; dropping it."
            rm -f -- "$f" "$f.sig"
        fi
    done
    # The legacy NVIDIA edition installs matching headers in the live root
    # itself, and those reach the target with it.
    if ! compgen -G "$dir/linux-headers-[0-9]*.pkg.tar.zst" >/dev/null \
        && [[ "$(pacman -Q linux-headers 2>/dev/null)" != "linux-headers $kver" ]]; then
        echo "No staged headers match the live kernel, so the offline wl driver set is left out; build with --refresh to stage one."
        wl_unused=true
    fi
else
    wl_unused=true
fi

files=() names=() unindexed=()
for f in "$dir"/*.pkg.tar.zst; do
    [[ -f "$f" ]] || continue
    # Installed by file name rather than from the repo, so these stay whether
    # or not the live root has them: install-gpu-drivers picks the NVIDIA
    # drivers by PCI match, and post-install-boot the wl set on the Macs that
    # need it.
    case "${f##*/}" in
        *nvidia*|libxnvctrl*)
            continue ;;
        broadcom-wl-dkms-[0-9]*|dkms-[0-9]*|linux-headers-[0-9]*|pahole-[0-9]*)
            [[ "$wl_unused" == true ]] && unindexed+=("$f")
            continue ;;
    esac
    read -r name ver < <(pacman -Qp "$f" 2>/dev/null) || continue
    [[ "$(pacman -Q "$name" 2>/dev/null)" == "$name $ver" ]] || continue
    files+=("$f")
    names+=("$name")
done
for f in "${unindexed[@]}"; do
    rm -f -- "$f" "$f.sig"
done
(( ${#unindexed[@]} > 0 )) && echo "Dropped ${#unindexed[@]} wl driver packages this kernel cannot use."
(( ${#names[@]} > 0 )) && [[ -f "$db" ]] || exit 0

# The db goes first: a file removed while the db still lists it would make any
# install that reaches for it fail to download.
if ! repo-remove -q "$db" "${names[@]}"; then
    echo "Could not update $db; keeping every bundled package." >&2
    exit 0
fi
rm -f -- "$dir"/mainstream.{db,files}.tar.gz.old
for f in "${files[@]}"; do
    rm -f -- "$f" "$f.sig"
done
echo "Dropped ${#names[@]} bundled packages the live root already has: ${names[*]}"
