#!/usr/bin/env bash
# check_deps.sh — Dependency checker for claudux tmux plugin
# Validates required tools are available. Warns via tmux display-message
# without crashing tmux. Returns non-zero if any dependency is missing.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# check_dependencies — check all required dependencies
# Returns 0 if all present, 1 if any missing
check_dependencies() {
    local missing=0

    # Check bash version (need 4.0+)
    local bash_major="${BASH_VERSINFO[0]}"
    if [[ "$bash_major" -lt 4 ]]; then
        tmux display-message \
            "claudux: Bash 4.0+ required (found $BASH_VERSION). macOS: brew install bash" \
            2>/dev/null || true
        missing=1
    fi

    # Check jq
    if ! command -v jq >/dev/null 2>&1; then
        tmux display-message \
            "claudux: jq required. Install: brew install jq / sudo apt install jq" \
            2>/dev/null || true
        missing=1
    fi

    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        tmux display-message \
            "claudux: curl required. Install: brew install curl / sudo apt install curl" \
            2>/dev/null || true
        missing=1
    fi

    return $missing
}

# When executed directly (not sourced), run the check
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    exit $?
fi
