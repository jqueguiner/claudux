#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

rotate_key=$(get_tmux_option "@claudux_rotate_key" "R")
label_key=$(get_tmux_option "@claudux_label_key" "T")
help_key=$(get_tmux_option "@claudux_help_key" "H")
label_mode=$(get_tmux_option "@claudux_label_mode" "$CLAUDUX_DEFAULT_LABEL_MODE")

help_text="
 claudux — Claude API usage monitor

 KEYBINDINGS
   Ctrl+B ${help_key}   Show this help
   Ctrl+B ${rotate_key}   Rotate profile
   Ctrl+B ${label_key}   Toggle labels (current: ${label_mode})

 SEGMENTS
   #{claudux_weekly}    Weekly usage
   #{claudux_monthly}   Monthly usage
   #{claudux_sonnet}    Sonnet model usage
   #{claudux_opus}      Opus model usage
   #{claudux_reset}     Reset countdowns
   #{claudux_profile}   Active profile
   #{claudux_email}     Account email
   #{claudux_cost}      Cost estimate (weekly/monthly)
   #{claudux_velocity}  Token velocity (tokens/h + trend)
   #{claudux_status}    Error / stale indicator

 COMMANDS
   claudux-setup install       Add to tmux.conf
   claudux-setup uninstall     Remove from tmux.conf
   claudux-setup status        Show status & deps
   claudux-setup profile list  List profiles
   claudux-setup profile add   Add profile (with login)

 OPTIONS (set -g @option value)
   @claudux_label_mode    verbose | compact
   @claudux_bar_length    5-30 (default: 10)
   @claudux_warning_threshold   (default: 50)
   @claudux_critical_threshold  (default: 80)
   @claudux_refresh_interval    seconds (default: 300)

 man claudux  for full documentation
"

tmux_version=$(tmux -V | sed 's/[^0-9.]//g')

if printf '%s\n3.3\n' "$tmux_version" | sort -V | head -1 | grep -q '^3\.3'; then
    tmux display-popup -w 55 -h 35 -T " claudux help " -E "echo \"$help_text\"; read -n1 -s -r -p ' Press any key to close'"
else
    tmux display-message "claudux: run 'man claudux' for help (popup requires tmux >= 3.3)"
fi
