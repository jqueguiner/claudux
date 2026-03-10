#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

current=$(get_tmux_option "@claudux_label_mode" "$CLAUDUX_DEFAULT_LABEL_MODE")

if [[ "$current" == "verbose" ]]; then
    tmux set -g @claudux_label_mode compact
    tmux display-message "claudux: compact labels"
else
    tmux set -g @claudux_label_mode verbose
    tmux display-message "claudux: verbose labels"
fi
