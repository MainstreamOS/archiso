#!/usr/bin/env bash
# Re-key the GNOME Keyring login collection after a system password change.
# Passwords are read from OLD_PASSWORD / NEW_PASSWORD environment variables,
# or as two lines on stdin (old, then new) as a fallback.
#
# Must run as the owning user (no pkexec) — the keyring daemon lives in
# the user's session bus.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Read passwords from environment (preferred) or stdin (fallback) ───────────
OLD_PASS="${OLD_PASSWORD:-}"
NEW_PASS="${NEW_PASSWORD:-}"
unset OLD_PASSWORD NEW_PASSWORD  # scrub from environment immediately

if [[ -z "$OLD_PASS" || -z "$NEW_PASS" ]]; then
    # Fallback: read from stdin (two lines: old, then new)
    IFS= read -r OLD_PASS
    IFS= read -r NEW_PASS
fi

if [[ -z "$OLD_PASS" || -z "$NEW_PASS" ]]; then
    echo "Both old and new passwords are required (via OLD_PASSWORD/NEW_PASSWORD env vars or stdin)." >&2
    exit 1
fi

# ── Ensure the keyring daemon is reachable ───────────────────────────────────
if ! busctl --user introspect org.freedesktop.secrets \
        /org/freedesktop/secrets/collection/login &>/dev/null; then
    echo "Login keyring not found on session bus — nothing to re-key." >&2
    exit 0
fi

# ── Open a plain-text Secret Service session ─────────────────────────────────
SESSION=$(busctl --user call org.freedesktop.secrets \
    /org/freedesktop/secrets \
    org.freedesktop.Secret.Service \
    OpenSession sv plain s "" 2>/dev/null \
    | grep -oP '"/org/freedesktop/secrets/session/[^"]*"' \
    | tr -d '"')

if [[ -z "$SESSION" ]]; then
    echo "Could not open a Secret Service session." >&2
    exit 1
fi

# ── Convert a string to busctl ay (array-of-byte) arguments ─────────────────
# Outputs: <length> <byte1> <byte2> ...
pass_to_ay() {
    local pass="$1"
    local len=${#pass}
    local args="$len"
    local i
    for ((i = 0; i < len; i++)); do
        args+=" $(printf '%d' "'${pass:$i:1}")"
    done
    echo "$args"
}

OLD_AY=$(pass_to_ay "$OLD_PASS")
NEW_AY=$(pass_to_ay "$NEW_PASS")

# ── Call ChangeWithMasterPassword ────────────────────────────────────────────
# Signature: (oayays)(oayays)  — two Secret structs (session, params, value, content_type)
# params (first ay) is empty for the "plain" algorithm.
# shellcheck disable=SC2086
busctl --user call org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection \
    ChangeWithMasterPassword \
    "(oayays)(oayays)" \
    "$SESSION" 0 $OLD_AY "text/plain" \
    "$SESSION" 0 $NEW_AY "text/plain" 2>/dev/null

echo "Keyring re-keyed successfully." >&2
