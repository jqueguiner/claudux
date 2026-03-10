#!/usr/bin/env bash
# claudux — Claude API usage monitor for tmux
# TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

# Run dependency check (non-blocking — warns but doesn't crash)
"$CURRENT_DIR/scripts/check_deps.sh"

# Format string interpolation will be added in Phase 5
# For now, this stub ensures the plugin loads without errors
