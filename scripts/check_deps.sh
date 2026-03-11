#!/usr/bin/env bash
# check_deps.sh — Dependency checker for claudux tmux plugin
# Validates required tools are available. Warns via tmux display-message
# without crashing tmux. Returns non-zero if any dependency is missing.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# check_dependencies — check all required dependencies
# Returns 0 if all present, 1 if any missing
_install_hint() {
    local pkg="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        printf 'brew install %s' "$pkg"
    elif command -v apt-get >/dev/null 2>&1; then
        printf 'sudo apt install %s' "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
        printf 'sudo dnf install %s' "$pkg"
    elif command -v pacman >/dev/null 2>&1; then
        printf 'sudo pacman -S %s' "$pkg"
    elif command -v zypper >/dev/null 2>&1; then
        printf 'sudo zypper install %s' "$pkg"
    elif command -v apk >/dev/null 2>&1; then
        printf 'apk add %s' "$pkg"
    else
        printf 'install %s via your package manager' "$pkg"
    fi
}

check_dependencies() {
    local missing=0

    local bash_major="${BASH_VERSINFO[0]}"
    if [[ "$bash_major" -lt 4 ]]; then
        tmux display-message \
            "claudux: Bash 4.0+ required (found $BASH_VERSION). $(_install_hint bash)" \
            2>/dev/null || true
        missing=1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        tmux display-message \
            "claudux: jq required. $(_install_hint jq)" \
            2>/dev/null || true
        missing=1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        tmux display-message \
            "claudux: curl required. $(_install_hint curl)" \
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
