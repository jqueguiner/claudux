#!/usr/bin/env bash
# claudux.sh — Single dispatcher for all #{claudux_*} format string calls
# Called by tmux via: #($PLUGIN_DIR/scripts/claudux.sh SEGMENT_NAME)
# Routes segment name to appropriate render_* function from render.sh
# Triggers background cache refresh when stale (non-blocking)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/render.sh"

if [[ "$(get_tmux_option "@claudux_auto_profile" "off")" == "on" ]]; then
    source "$CURRENT_DIR/auto_profile.sh"
fi

# ─── Background Refresh ────────────────────────────────────────────────────
# If cache is stale, spawn fetch.sh in background via tmux run-shell -b
# PID file prevents duplicate fetches; fetch.sh has its own lock as second guard

write_live_cache 2>/dev/null &

if is_cache_stale; then
    cache_dir="$(get_cache_dir 2>/dev/null)"
    if [[ -n "$cache_dir" ]]; then
        pid_file="${cache_dir}/fetch.pid"
        # Only spawn if no fetch is already running
        if [[ ! -f "$pid_file" ]] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
            tmux run-shell -b "echo \$\$ > '${pid_file}' && '${CURRENT_DIR}/fetch.sh'; rm -f '${pid_file}'" 2>/dev/null
        fi
    fi
fi

# ─── Segment Routing ───────────────────────────────────────────────────────
# Route to render function based on segment name argument

case "${1:-}" in
    weekly)
        [[ "$(get_tmux_option "@claudux_show_weekly" "$CLAUDUX_DEFAULT_SHOW_WEEKLY")" == "on" ]] && render_weekly
        ;;
    monthly)
        [[ "$(get_tmux_option "@claudux_show_monthly" "$CLAUDUX_DEFAULT_SHOW_MONTHLY")" == "on" ]] && render_monthly
        ;;
    sonnet)
        [[ "$(get_tmux_option "@claudux_show_model" "$CLAUDUX_DEFAULT_SHOW_MODEL")" == "on" ]] && render_model_sonnet
        ;;
    opus)
        [[ "$(get_tmux_option "@claudux_show_model" "$CLAUDUX_DEFAULT_SHOW_MODEL")" == "on" ]] && render_model_opus
        ;;
    reset)
        [[ "$(get_tmux_option "@claudux_show_reset" "$CLAUDUX_DEFAULT_SHOW_RESET")" == "on" ]] && render_reset
        ;;
    email)
        [[ "$(get_tmux_option "@claudux_show_email" "$CLAUDUX_DEFAULT_SHOW_EMAIL")" == "on" ]] && render_email
        ;;
    cost)
        [[ "$(get_tmux_option "@claudux_show_cost" "$CLAUDUX_DEFAULT_SHOW_COST")" == "on" ]] && render_cost
        ;;
    velocity)
        [[ "$(get_tmux_option "@claudux_show_velocity" "$CLAUDUX_DEFAULT_SHOW_VELOCITY")" == "on" ]] && render_velocity
        ;;
    context)
        [[ "$(get_tmux_option "@claudux_show_context" "$CLAUDUX_DEFAULT_SHOW_CONTEXT")" == "on" ]] && render_context
        ;;
    model)
        [[ "$(get_tmux_option "@claudux_show_model_indicator" "$CLAUDUX_DEFAULT_SHOW_MODEL_INDICATOR")" == "on" ]] && render_model
        ;;
    burn)
        [[ "$(get_tmux_option "@claudux_show_burn" "$CLAUDUX_DEFAULT_SHOW_BURN")" == "on" ]] && render_burn_rate
        ;;
    cooldown)
        render_cooldown
        ;;
    sessions)
        [[ "$(get_tmux_option "@claudux_show_sessions" "$CLAUDUX_DEFAULT_SHOW_SESSIONS")" == "on" ]] && render_sessions
        ;;
    heartbeat)
        render_heartbeat
        ;;
    ratelimits)
        [[ "$(get_tmux_option "@claudux_show_rate_limits" "on")" == "on" ]] && render_rate_limit_history
        ;;
    predictor)
        [[ "$(get_tmux_option "@claudux_show_predictor" "on")" == "on" ]] && render_rate_limit_predictor
        ;;
    vitals)
        [[ "$(get_tmux_option "@claudux_show_vitals" "on")" == "on" ]] && render_vitals
        ;;
    profile)
        render_profile
        ;;
    status)
        err="$(render_error)"
        stale="$(render_stale_indicator)"
        output="${err}${stale}"
        [[ -n "$output" ]] && printf '%s' "$output"
        ;;
    *)
        # Unknown segment — silent fail (don't pollute status bar)
        ;;
esac
