# remove from airootfs!
# Run by zzzz90-prune-bundled-pkgs.hook while the ISO is built. It sits in the
# hooks directory so the zzzz99 hook removes it with the other build-only files.
set -uo pipefail

# DKMS signs what it builds with a key it makes on its first build. Left here,
# one private key would ship on the ISO and be copied to every install.
rm -f /var/lib/dkms/mok.key /var/lib/dkms/mok.pub

dir=/usr/local/share/pkgs
db="$dir/mainstream.db.tar.gz"
[[ -d "$dir" ]] || exit 0

# The staged wl driver builds against the live root's Mainstream kernel headers;
# without matching ones post-install-boot takes it from the repositories.
# By exact name: pacman -Q answers with a provider.
wl_unused=true
hver=$(pacman -Q mainstream-headers 2>/dev/null) || hver=""
if [[ "$hver" == "mainstream-headers "* \
      && "$(pacman -Q mainstream 2>/dev/null)" == "mainstream ${hver#* }" ]]; then
    wl_unused=false
elif [[ -n "$hver" ]]; then
    echo "The live root's $hver does not match its kernel, so the offline wl driver is left out."
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
        broadcom-wl-dkms-[0-9]*)
            [[ "$wl_unused" == true ]] && unindexed+=("$f")
            continue ;;
        dkms-[0-9]*|linux-headers-[0-9]*|pahole-[0-9]*)
            # The db never lists these, and repo-remove refuses a name it does not list.
            unindexed+=("$f")
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
(( ${#unindexed[@]} > 0 )) && echo "Dropped ${#unindexed[@]} wl driver packages the image does not use: ${unindexed[*]##*/}"
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
