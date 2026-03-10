#!/usr/bin/env bash
# claudux.sh — Single dispatcher for all #{claudux_*} format string calls
# Called by tmux via: #($PLUGIN_DIR/scripts/claudux.sh SEGMENT_NAME)
# Routes segment name to appropriate render_* function from render.sh
# Triggers background cache refresh when stale (non-blocking)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/render.sh"

# ─── Background Refresh ────────────────────────────────────────────────────
# If cache is stale, spawn fetch.sh in background via tmux run-shell -b
# PID file prevents duplicate fetches; fetch.sh has its own lock as second guard

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
    weekly)  render_weekly ;;
    monthly) render_monthly ;;
    sonnet)  render_model_sonnet ;;
    opus)    render_model_opus ;;
    reset)   render_reset ;;
    email)   render_email ;;
    status)
        # Combine error + stale indicators into single output
        err="$(render_error)"
        stale="$(render_stale_indicator)"
        output="${err}${stale}"
        [[ -n "$output" ]] && printf '%s' "$output"
        ;;
    *)
        # Unknown segment — silent fail (don't pollute status bar)
        ;;
esac
