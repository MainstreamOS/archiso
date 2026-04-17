#!/usr/bin/env bash
# apply-theme.sh — transactional theme application
#
# Flow: back up the live config, stage the theme's config.json + wallpaperPath,
# run switchwall.sh --noswitch to regenerate colors, then validate that matugen
# actually produced a usable colors.json. On validation failure the backup is
# restored so the shell never sees a half-applied theme.
#
# Usage: apply-theme.sh <slug>

set -euo pipefail

SLUG="${1:-}"
[ -z "$SLUG" ] && { echo "usage: apply-theme.sh <slug>" >&2; exit 2; }

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCHWALL="$SCRIPT_DIR/../colors/switchwall.sh"

THEMES_DIR="$XDG_CONFIG_HOME/mainstream/themes"
THEME_DIR="$THEMES_DIR/$SLUG"
LAST_APPLIED="$THEMES_DIR/last-applied.txt"

SHELL_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
COLORS_JSON="$XDG_STATE_HOME/quickshell/user/generated/colors.json"

[ -d "$THEME_DIR" ] || { echo "theme dir missing: $THEME_DIR" >&2; exit 3; }
[ -f "$THEME_DIR/config.json" ] || { echo "theme config missing" >&2; exit 4; }

# Resolve wallpaper (stored as meta.wallpaperFile, relative to $THEME_DIR)
WP_FILE=""
if [ -f "$THEME_DIR/meta.json" ]; then
    WP_FILE=$(jq -r '.wallpaperFile // ""' "$THEME_DIR/meta.json" 2>/dev/null || echo "")
fi
WP_ABS=""
[ -n "$WP_FILE" ] && [ -f "$THEME_DIR/$WP_FILE" ] && WP_ABS="$THEME_DIR/$WP_FILE"

# ── 1. Backup live config for rollback ──────────────────────────────────────
mkdir -p "$(dirname "$SHELL_CONFIG")"
BACKUP=""
if [ -f "$SHELL_CONFIG" ]; then
    BACKUP=$(mktemp --tmpdir="$(dirname "$SHELL_CONFIG")" config.json.backup.XXXXXX)
    cp -f "$SHELL_CONFIG" "$BACKUP"
fi

rollback() {
    local reason="$1"
    echo "[apply-theme] validation failed: $reason — rolling back" >&2
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        mv -f "$BACKUP" "$SHELL_CONFIG"
        BACKUP=""
    fi
    exit 5
}

cleanup() {
    [ -n "$BACKUP" ] && [ -f "$BACKUP" ] && rm -f "$BACKUP"
}
trap cleanup EXIT

# ── 2. Stage merged config.json with wallpaperPath rewritten ────────────────
TMP=$(mktemp --tmpdir="$(dirname "$SHELL_CONFIG")" config.json.XXXXXX)
if [ -n "$WP_ABS" ]; then
    jq --arg p "$WP_ABS" '.background.wallpaperPath = $p' "$THEME_DIR/config.json" > "$TMP" \
        || { rm -f "$TMP"; rollback "failed to stage config.json"; }
else
    cp -f "$THEME_DIR/config.json" "$TMP" || { rm -f "$TMP"; rollback "failed to copy config.json"; }
fi
mv -f "$TMP" "$SHELL_CONFIG"

# ── 3. Regenerate colors via switchwall --noswitch ──────────────────────────
if [ -x "$SWITCHWALL" ] || [ -f "$SWITCHWALL" ]; then
    bash "$SWITCHWALL" --noswitch || rollback "switchwall.sh exited non-zero"
else
    rollback "switchwall.sh not found at $SWITCHWALL"
fi

# ── 4. Validate colors.json: exists, parses, has m3primary ──────────────────
[ -f "$COLORS_JSON" ] || rollback "colors.json missing at $COLORS_JSON"
jq -e . "$COLORS_JSON" >/dev/null 2>&1 || rollback "colors.json is not valid JSON"
jq -e '.m3primary // empty' "$COLORS_JSON" >/dev/null 2>&1 \
    || rollback "colors.json missing m3primary token"

# ── 5. Record last-applied (consumed by ThemesConfig for ordering) ─────────
mkdir -p "$THEMES_DIR"
printf '%s' "$SLUG" > "$LAST_APPLIED.tmp" && mv -f "$LAST_APPLIED.tmp" "$LAST_APPLIED"

# ── 6. Reload hyprland so matugen's hypr color template output is picked up ─
command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true

echo "OK"
