# /etc/profile.d/calamares-hidpi.sh
# Set Qt's scale factor for the live Calamares session when running on a
# HiDPI display (4K+ native), so the installer text isn't microscopic.
# Live-only — removed from the installed target by
# /usr/local/bin/cleanup-unused-drivers so it doesn't double-scale Qt
# apps on top of the user's compositor scale.
#
# Triggers when the largest connected output is >= 3000 px wide.
# Heuristic, not bulletproof — a triple-1080p setup would total >3000px
# but each individual display is normal-DPI; we read per-monitor sizes
# from /sys/class/drm to avoid that false positive.

# Skip if Qt scale factor was already set by the user / boot cmdline.
[ -n "${QT_SCALE_FACTOR:-}" ] && return 0

# Skip on non-graphical TTYs — saves cost in serial console contexts.
case "${XDG_SESSION_TYPE:-}" in
    wayland|x11) ;;
    *) return 0 ;;
esac

# Find the widest connected display. Some drivers report
# `connected 3840x2160+0+0`; we just need the first number after
# `connected`.
widest=0
for status in /sys/class/drm/card*-*/status; do
    [ -r "$status" ] || continue
    [ "$(cat "$status" 2>/dev/null)" = "connected" ] || continue
    modes="${status%/status}/modes"
    [ -r "$modes" ] || continue
    # First mode line is the preferred resolution (e.g. "3840x2160").
    pref=$(head -n1 "$modes" 2>/dev/null)
    case "$pref" in
        *x*)
            width=${pref%x*}
            [ "$width" -gt "$widest" ] 2>/dev/null && widest=$width
            ;;
    esac
done

if [ "$widest" -ge 3000 ] 2>/dev/null; then
    export QT_SCALE_FACTOR=1.5
fi
