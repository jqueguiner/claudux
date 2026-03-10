#!/usr/bin/env bash
# claudux — Claude API usage monitor for tmux
# TPM plugin entry point
# Supports: TPM install (set -g @plugin 'user/claudux') and manual (run-shell path/to/claudux.tmux)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

# Run dependency check (non-blocking — warns but doesn't crash)
"$CURRENT_DIR/scripts/check_deps.sh"

# ─── Format String Registration ────────────────────────────────────────────
# Maps #{claudux_*} placeholders to dispatcher script calls.
# Uses bash parameter expansion (tmux-battery pattern) — not sed.
# Each placeholder resolves to: #($CURRENT_DIR/scripts/claudux.sh SEGMENT)

claudux_interpolation=(
    "\#{claudux_weekly}"
    "\#{claudux_monthly}"
    "\#{claudux_sonnet}"
    "\#{claudux_opus}"
    "\#{claudux_reset}"
    "\#{claudux_email}"
    "\#{claudux_status}"
)

claudux_commands=(
    "#($CURRENT_DIR/scripts/claudux.sh weekly)"
    "#($CURRENT_DIR/scripts/claudux.sh monthly)"
    "#($CURRENT_DIR/scripts/claudux.sh sonnet)"
    "#($CURRENT_DIR/scripts/claudux.sh opus)"
    "#($CURRENT_DIR/scripts/claudux.sh reset)"
    "#($CURRENT_DIR/scripts/claudux.sh email)"
    "#($CURRENT_DIR/scripts/claudux.sh status)"
)

# do_interpolation — Replace all #{claudux_*} placeholders in a string
# Uses bash parameter expansion: ${var//pattern/replacement}
do_interpolation() {
    local all_interpolated="$1"
    for ((i = 0; i < ${#claudux_commands[@]}; i++)); do
        all_interpolated="${all_interpolated//${claudux_interpolation[$i]}/${claudux_commands[$i]}}"
    done
    printf '%s' "$all_interpolated"
}

# update_tmux_option — Read a tmux option, interpolate format strings, write back
update_tmux_option() {
    local option="$1"
    local option_value
    option_value="$(get_tmux_option "$option" "")"
    local new_option_value
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    # Register format strings in status-right and status-left
    update_tmux_option "status-right"
    update_tmux_option "status-left"

    # Ensure status-right-length is sufficient for multiple segments
    # Default tmux value (40) truncates multi-segment displays
    # Only increase — never decrease a user's explicit setting
    local current_length
    current_length="$(get_tmux_option "status-right-length" "40")"
    if [[ "$current_length" -lt 200 ]] 2>/dev/null; then
        set_tmux_option "status-right-length" "200"
    fi

    # Trigger initial data fetch in background
    # First render will show empty (render functions return silently on missing cache)
    # After fetch completes (a few seconds), next status-interval tick shows data
    tmux run-shell -b "$CURRENT_DIR/scripts/fetch.sh"
}

main
