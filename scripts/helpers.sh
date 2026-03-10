#!/usr/bin/env bash
# helpers.sh — Shared utilities for claudux tmux plugin
# Sourced by all claudux scripts. Never executed directly.

# Resolve plugin root directory
CLAUDUX_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source default values
source "$CLAUDUX_PLUGIN_DIR/config/defaults.sh"

# Cache platform detection result (detect once, reuse)
_CLAUDUX_PLATFORM=""

# get_platform — returns "linux" or "darwin"
get_platform() {
    if [[ -z "$_CLAUDUX_PLATFORM" ]]; then
        local uname_out
        uname_out="$(uname -s)"
        case "$uname_out" in
            Linux*)  _CLAUDUX_PLATFORM="linux" ;;
            Darwin*) _CLAUDUX_PLATFORM="darwin" ;;
            *)       _CLAUDUX_PLATFORM="linux" ;;  # Default to linux for unknown
        esac
    fi
    echo "$_CLAUDUX_PLATFORM"
}

# get_tmux_option — read tmux global option with fallback default
# Usage: get_tmux_option "@option_name" "default_value"
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value

    # Guard against tmux not running
    option_value="$(tmux show-option -gqv "$option" 2>/dev/null)" || true

    if [[ -z "$option_value" ]]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# set_tmux_option — set tmux global option
# Usage: set_tmux_option "@option_name" "value"
set_tmux_option() {
    tmux set-option -gq "$1" "$2" 2>/dev/null || true
}

# get_file_mtime — return file modification time as epoch seconds
# Cross-platform: uses stat -c on Linux, stat -f on macOS
get_file_mtime() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    if [[ "$(get_platform)" == "darwin" ]]; then
        stat -f %m "$file"
    else
        stat -c %Y "$file"
    fi
}

# get_cache_dir — return cache directory path, creating if missing
get_cache_dir() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir" || {
            echo "ERROR: Cannot create cache directory: $cache_dir" >&2
            return 1
        }
    fi
    echo "$cache_dir"
}

# get_config_dir — return config directory path
get_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/claudux"
}

# get_plugin_dir — return the plugin root directory
get_plugin_dir() {
    echo "$CLAUDUX_PLUGIN_DIR"
}
