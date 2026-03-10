#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/profiles.sh"

auto_switch_profile() {
    local pane_pid
    pane_pid=$(tmux display-message -p '#{pane_pid}' 2>/dev/null) || return 0
    [[ -z "$pane_pid" ]] && return 0

    local claude_dir=""
    local child_pids
    if [[ "$(get_platform)" == "darwin" ]]; then
        child_pids=$(pgrep -P "$pane_pid" 2>/dev/null)
    else
        child_pids=$(pgrep -P "$pane_pid" 2>/dev/null)
    fi

    local pid
    for pid in $pane_pid $child_pids; do
        local env_val
        if [[ "$(get_platform)" == "darwin" ]]; then
            env_val=$(ps -E -p "$pid" 2>/dev/null | tr ' ' '\n' | sed -n 's/^CLAUDE_CONFIG_DIR=//p' | head -1)
        else
            env_val=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^CLAUDE_CONFIG_DIR=//p' | head -1)
        fi
        if [[ -n "$env_val" ]]; then
            claude_dir="$env_val"
            break
        fi
    done

    local profiles_data
    profiles_data=$(_read_profiles)
    local active
    active=$(printf '%s' "$profiles_data" | jq -r '.active')

    if [[ -n "$claude_dir" ]]; then
        local match
        match=$(printf '%s' "$profiles_data" | jq -r --arg dir "$claude_dir" \
            '.profiles | to_entries[] | select(.value.claude_config_dir == $dir) | .key' | head -1)
        if [[ -n "$match" ]] && [[ "$match" != "$active" ]]; then
            local updated
            updated=$(printf '%s' "$profiles_data" | jq --arg n "$match" '.active = $n')
            _write_profiles "$updated"
        fi
    fi
}

auto_switch_profile
