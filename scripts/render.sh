#!/usr/bin/env bash
# render.sh — Progress bar rendering for claudux tmux plugin
# Produces tmux-formatted strings with Unicode progress bars and color coding.
# Each render_* function outputs a self-contained segment for the status bar.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"

# render_bar — Core progress bar renderer
# Parameters: $1 = percentage (integer 0-100), $2 = bar_length (default 10)
# Outputs: tmux-formatted progress bar string with color coding
# Example: [#[fg=colour34]█████#[default]░░░░░]
render_bar() {
    local pct="$1"
    local bar_length="${2:-10}"

    # Clamp percentage
    [[ $pct -lt 0 ]] && pct=0
    [[ $pct -gt 100 ]] && pct=100

    # Read thresholds once (each get_tmux_option forks a process)
    local warning_threshold critical_threshold
    warning_threshold=$(get_tmux_option "@claudux_warning_threshold" "$CLAUDUX_DEFAULT_WARNING_THRESHOLD")
    critical_threshold=$(get_tmux_option "@claudux_critical_threshold" "$CLAUDUX_DEFAULT_CRITICAL_THRESHOLD")

    # Color selection based on thresholds
    local color
    if [[ $pct -ge $critical_threshold ]]; then
        color="colour196"  # Red
    elif [[ $pct -ge $warning_threshold ]]; then
        color="colour220"  # Yellow
    else
        color="colour34"   # Green
    fi

    # Calculate filled segments (round to nearest integer)
    local filled=$(( (pct * bar_length + 50) / 100 ))
    local empty=$(( bar_length - filled ))

    # Build bar string
    local bar="[#[fg=${color}]"
    local i
    for (( i = 0; i < filled; i++ )); do bar+="█"; done
    bar+="#[default]"
    for (( i = 0; i < empty; i++ )); do bar+="░"; done
    bar+="]"

    printf '%s' "$bar"
}

# render_weekly — Render weekly consumption progress bar
# Reads cache, extracts weekly.used/weekly.limit, outputs labeled bar
# Output: #[fg=colour245]W:#[default] [████░░░░░░] XX%
# Returns 0 silently if cache missing, errored, or limit=0
render_weekly() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.weekly.used // 0')
    limit=$(printf '%s' "$cache_data" | jq -r '.weekly.limit // 0')

    # Skip if limit is 0 (unknown)
    [[ "$limit" -eq 0 ]] 2>/dev/null && return 0

    # Calculate percentage
    local pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0

    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")

    printf '#[fg=colour245]W:#[default] %s %d%%' "$(render_bar "$pct" "$bar_length")" "$pct"
}

# render_monthly — Render monthly consumption progress bar
# Reads cache, extracts monthly.used/monthly.limit, outputs labeled bar
# Output: #[fg=colour245]M:#[default] [████░░░░░░] XX%
# Returns 0 silently if cache missing, errored, or limit=0
render_monthly() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.monthly.used // 0')
    limit=$(printf '%s' "$cache_data" | jq -r '.monthly.limit // 0')

    # Skip if limit is 0 (unknown)
    [[ "$limit" -eq 0 ]] 2>/dev/null && return 0

    # Calculate percentage
    local pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0

    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")

    printf '#[fg=colour245]M:#[default] %s %d%%' "$(render_bar "$pct" "$bar_length")" "$pct"
}

# render_model_sonnet — Render Sonnet model usage progress bar
# Reads cache, extracts models.sonnet.used/models.sonnet.limit, outputs labeled bar
# Output: #[fg=colour245]S:#[default] [████░░░░░░] XX%
# Returns 0 silently if cache missing, errored, model not in cache, or limit=0
render_model_sonnet() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    # Check if sonnet model exists in cache
    printf '%s' "$cache_data" | jq -e '.models.sonnet' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.models.sonnet.used // 0')
    limit=$(printf '%s' "$cache_data" | jq -r '.models.sonnet.limit // 0')

    # Skip if limit is 0 (org mode doesn't expose model limits)
    [[ "$limit" -eq 0 ]] 2>/dev/null && return 0

    # Calculate percentage
    local pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0

    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")

    printf '#[fg=colour245]S:#[default] %s %d%%' "$(render_bar "$pct" "$bar_length")" "$pct"
}

# render_model_opus — Render Opus model usage progress bar
# Reads cache, extracts models.opus.used/models.opus.limit, outputs labeled bar
# Output: #[fg=colour245]O:#[default] [████░░░░░░] XX%
# Returns 0 silently if cache missing, errored, model not in cache, or limit=0
render_model_opus() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    # Check if opus model exists in cache
    printf '%s' "$cache_data" | jq -e '.models.opus' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.models.opus.used // 0')
    limit=$(printf '%s' "$cache_data" | jq -r '.models.opus.limit // 0')

    # Skip if limit is 0 (org mode doesn't expose model limits)
    [[ "$limit" -eq 0 ]] 2>/dev/null && return 0

    # Calculate percentage
    local pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0

    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")

    printf '#[fg=colour245]O:#[default] %s %d%%' "$(render_bar "$pct" "$bar_length")" "$pct"
}
