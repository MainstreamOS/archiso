#!/usr/bin/env bash
# Renders the SVG masters in this directory into the PNGs Calamares loads from
# the parent branding directory. Run after any SVG edit:
#   ./render-slides.sh
#
# Slideshow PNGs are 3810x1785 (1270:595 = 2.1345:1) — measured against the
# slideshow QQuickWidget that Calamares actually allocates inside our locked
# 1500x800 branded window (window size pinned via setFixedSize, see
# CalamaresWindow.cpp). The widget ends up 1270x595 logical pixels after
# the cumulative pane chrome (sidebar, outer/inner margins, title, nav,
# #viewManager padding, QTabWidget pane padding, ExecutionViewStep layout
# margin from PM_LayoutLeftMargin); rather than chase each contributor and
# patch them to zero, the SVG masters are sized to the resulting aspect
# directly. 3810x1785 is exactly 3× the measured widget size, so the PNG
# downscales by an integer factor on the user's display.
#
# The SVG masters use a viewBox of 1920x899.5276 — float height for exact
# 1270:595 = 2.1345:1, so rsvg-convert renders 3810x1785 with zero
# rounding error.
#
# Embedded Quickshell screenshots are still at their source resolution and
# will be upscaled by rsvg — they read fine at the slide tile size, but if
# a slide image looks soft, re-capture the screenshot at 1800px wide minimum.
# The welcome PNG is 1440x1020 with a transparent background (Calamares
# centres it on the welcome page; the laptop mockup sits inside the
# transparent canvas).
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
OUT="$(realpath ..)"

render() {
    local svg="$1" png="$2" w="$3" h="$4" bg="${5:-}"
    local bgflag=()
    [[ -n "$bg" ]] && bgflag=(--background-color "$bg")
    echo ">>> $svg  →  $png  (${w}x${h})"
    rsvg-convert --width "$w" --height "$h" --keep-aspect-ratio "${bgflag[@]}" \
        "$svg" -o "$OUT/$png"
}

render slide_1_welcome.svg       slide_welcome.png       3810 1785 "#0B0D12"
render slide_2_themes.svg        slide_themes.png        3810 1785 "#0B0D12"
render slide_3_layouts.svg       slide_layouts.png       3810 1785 "#0B0D12"
render slide_4_keybinds.svg      slide_keybinds.png      3810 1785 "#0B0D12"
render slide_5_maintenance.svg   slide_maintenance.png   3810 1785 "#0B0D12"
render slide_6_almost_there.svg  slide_almost_there.png  3810 1785 "#0B0D12"

render welcome.svg               welcome.png             3810 1785

echo ""
echo "Done. Output PNGs live in: $OUT"
