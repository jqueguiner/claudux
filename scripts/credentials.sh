#!/usr/bin/env bash
# credentials.sh — API key loading for claudux tmux plugin
# Loads credentials from environment variable or config file.
# Never passes keys as CLI arguments (visible in ps aux).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# load_api_key — Load API key from env var or config file
# Priority: $ANTHROPIC_ADMIN_API_KEY env var > config file
# Returns 0 and echoes key on success, 1 on failure
load_api_key() {
    # Priority 1: Environment variable
    if [[ -n "${ANTHROPIC_ADMIN_API_KEY:-}" ]]; then
        echo "$ANTHROPIC_ADMIN_API_KEY"
        return 0
    fi

    # Priority 2: Config file with strict permissions
    local config_dir
    config_dir="$(get_config_dir)"
    local config_file="${config_dir}/credentials"

    if [[ -f "$config_file" ]]; then
        # Verify permissions are 600
        local perms
        if [[ "$(get_platform)" == "darwin" ]]; then
            perms=$(stat -f %Lp "$config_file")
        else
            perms=$(stat -c %a "$config_file")
        fi

        if [[ "$perms" != "600" ]]; then
            echo "claudux: ${config_file} has insecure permissions (${perms}). Expected 600." >&2
            return 1
        fi

        # Read first non-empty, non-comment line
        local key
        key=$(grep -v '^[[:space:]]*#' "$config_file" | grep -v '^[[:space:]]*$' | head -1)

        if [[ -n "$key" ]]; then
            echo "$key"
            return 0
        fi
    fi

    # No key found
    return 1
}

# get_key_type — Detect API key type
# Returns "admin" for org mode keys, "unknown" otherwise
# Usage: get_key_type "$key"
get_key_type() {
    local key="$1"

    if [[ "$key" == sk-ant-admin* ]]; then
        echo "admin"
    else
        echo "unknown"
    fi

    return 0
}
