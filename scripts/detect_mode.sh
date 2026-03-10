#!/usr/bin/env bash
# detect_mode.sh — Data source mode auto-detection for claudux tmux plugin
# Determines whether to use Admin API (org) or local JSONL logs (local).
# Respects @claudux_mode tmux option override.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/credentials.sh"

# detect_mode — Determine data source mode
# Priority: 1) @claudux_mode tmux option, 2) Admin API key, 3) local JSONL logs
# Outputs: mode name (org, local, none) to stdout
# Logs: detection reason to stderr
# Returns: 0 on success, 1 when no source available
detect_mode() {
    # Check for forced mode via tmux option
    local forced_mode
    forced_mode=$(get_tmux_option "@claudux_mode" "auto")

    if [[ "$forced_mode" == "org" ]]; then
        echo "claudux: using org mode (forced)" >&2
        echo "org"
        return 0
    fi

    if [[ "$forced_mode" == "local" ]]; then
        echo "claudux: using local mode (forced)" >&2
        echo "local"
        return 0
    fi

    # Auto-detection: forced_mode is "auto" or empty

    # Step 1: Try loading API key and check if it's an admin key
    local api_key
    api_key=$(load_api_key 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$api_key" ]]; then
        local key_type
        key_type=$(get_key_type "$api_key")
        if [[ "$key_type" == "admin" ]]; then
            echo "claudux: using org mode (admin key detected)" >&2
            echo "org"
            return 0
        fi
    fi

    # Step 2: Check for local Claude Code session logs
    if [[ -d "$HOME/.claude/projects" ]]; then
        local log_found
        log_found=$(find "$HOME/.claude/projects" -name "*.jsonl" -type f 2>/dev/null | head -1)
        if [[ -n "$log_found" ]]; then
            echo "claudux: using local mode (JSONL logs found)" >&2
            echo "local"
            return 0
        fi
    fi

    # Step 3: No data source available
    echo "claudux: no data source available" >&2
    echo "none"
    return 1
}

# When executed directly (not sourced), run detection
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_mode
    exit $?
fi
