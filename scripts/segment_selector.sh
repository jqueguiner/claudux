#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

_toggle() {
    local option="$1"
    local default="$2"
    local current
    current=$(get_tmux_option "$option" "$default")
    if [[ "$current" == "on" ]]; then
        tmux set -g "$option" off
    else
        tmux set -g "$option" on
    fi
    tmux refresh-client -S 2>/dev/null || true
}

_check() {
    local option="$1"
    local default="$2"
    local current
    current=$(get_tmux_option "$option" "$default")
    if [[ "$current" == "on" ]]; then
        printf '[x]'
    else
        printf '[ ]'
    fi
}

_label_check() {
    local current
    current=$(get_tmux_option "@claudux_label_mode" "$CLAUDUX_DEFAULT_LABEL_MODE")
    if [[ "$current" == "compact" ]]; then
        printf '[x]'
    else
        printf '[ ]'
    fi
}

segments=(
    "@claudux_show_weekly|$CLAUDUX_DEFAULT_SHOW_WEEKLY|Weekly Usage"
    "@claudux_show_monthly|$CLAUDUX_DEFAULT_SHOW_MONTHLY|Monthly Usage"
    "@claudux_show_model|$CLAUDUX_DEFAULT_SHOW_MODEL|Sonnet / Opus Breakdown"
    "@claudux_show_reset|$CLAUDUX_DEFAULT_SHOW_RESET|Reset Countdowns"
    "@claudux_show_cost|$CLAUDUX_DEFAULT_SHOW_COST|Cost Estimate"
    "@claudux_show_velocity|$CLAUDUX_DEFAULT_SHOW_VELOCITY|Token Velocity"
    "@claudux_show_context|$CLAUDUX_DEFAULT_SHOW_CONTEXT|Context Window"
    "@claudux_show_model_indicator|$CLAUDUX_DEFAULT_SHOW_MODEL_INDICATOR|Active Model"
    "@claudux_show_burn|$CLAUDUX_DEFAULT_SHOW_BURN|Burn Rate"
    "@claudux_show_sessions|$CLAUDUX_DEFAULT_SHOW_SESSIONS|Sessions"
    "@claudux_show_rate_limits|$CLAUDUX_DEFAULT_SHOW_RATE_LIMITS|Rate Limit History"
    "@claudux_show_predictor|$CLAUDUX_DEFAULT_SHOW_PREDICTOR|Rate Limit Predictor"
    "@claudux_show_vitals|$CLAUDUX_DEFAULT_SHOW_VITALS|System Vitals"
    "@claudux_show_email|$CLAUDUX_DEFAULT_SHOW_EMAIL|Account Email"
)

if [[ "${1:-}" == "toggle" ]]; then
    option="$2"
    default="$3"
    _toggle "$option" "$default"
    exec "$CURRENT_DIR/segment_selector.sh"
    exit 0
fi

if [[ "${1:-}" == "toggle-labels" ]]; then
    current=$(get_tmux_option "@claudux_label_mode" "$CLAUDUX_DEFAULT_LABEL_MODE")
    if [[ "$current" == "verbose" ]]; then
        tmux set -g @claudux_label_mode compact
    else
        tmux set -g @claudux_label_mode verbose
    fi
    tmux refresh-client -S 2>/dev/null || true
    exec "$CURRENT_DIR/segment_selector.sh"
    exit 0
fi

menu_args=(-T " claudux segments " -x C -y C)

i=1
for entry in "${segments[@]}"; do
    IFS='|' read -r option default label <<< "$entry"
    check=$(_check "$option" "$default")
    menu_args+=("${check} ${label}" "$i" "run-shell '${CURRENT_DIR}/segment_selector.sh toggle ${option} ${default}'")
    i=$((i + 1))
done

menu_args+=("" "" "")
label_check=$(_label_check)
menu_args+=("${label_check} Compact Labels" "$i" "run-shell '${CURRENT_DIR}/segment_selector.sh toggle-labels'")

tmux display-menu "${menu_args[@]}"
