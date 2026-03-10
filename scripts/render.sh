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

# render_reset — Render quota reset countdown
# Reads reset_at from cache weekly and monthly sections, picks nearest non-zero.
# Output: #[fg=colour245]R:#[default] 2h 15m
# Adaptive format: Xd Yh (>24h), Xh Ym (<24h), Xm (<1h)
# Returns 0 silently if both reset_at are 0/missing, or if reset is in the past.
render_reset() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    # Get reset_at from both sections
    local weekly_reset monthly_reset
    weekly_reset=$(printf '%s' "$cache_data" | jq -r '.weekly.reset_at // 0')
    monthly_reset=$(printf '%s' "$cache_data" | jq -r '.monthly.reset_at // 0')

    # Find nearest non-zero reset
    local reset_at=0
    if [[ "$weekly_reset" -gt 0 ]] && [[ "$monthly_reset" -gt 0 ]]; then
        if [[ "$weekly_reset" -le "$monthly_reset" ]]; then
            reset_at="$weekly_reset"
        else
            reset_at="$monthly_reset"
        fi
    elif [[ "$weekly_reset" -gt 0 ]]; then
        reset_at="$weekly_reset"
    elif [[ "$monthly_reset" -gt 0 ]]; then
        reset_at="$monthly_reset"
    fi

    # Silent return if no reset time known
    [[ "$reset_at" -le 0 ]] 2>/dev/null && return 0

    # Calculate remaining seconds
    local now remaining
    now=$(date +%s)
    remaining=$(( reset_at - now ))

    # Silent return if already past
    [[ "$remaining" -le 0 ]] && return 0

    # Format based on magnitude
    local days hours minutes time_str
    days=$(( remaining / 86400 ))
    hours=$(( (remaining % 86400) / 3600 ))
    minutes=$(( (remaining % 3600) / 60 ))

    if [[ "$days" -gt 0 ]]; then
        time_str="${days}d ${hours}h"
    elif [[ "$hours" -gt 0 ]]; then
        time_str="${hours}h ${minutes}m"
    else
        # Minimum 1m to avoid showing "0m"
        [[ "$minutes" -le 0 ]] && minutes=1
        time_str="${minutes}m"
    fi

    printf '#[fg=colour245]R:#[default] %s' "$time_str"
}

# render_email — Render account email
# Reads account.email from cache, truncates long emails.
# Output: #[fg=colour245]user@example.com#[default]
# Returns 0 silently if email is null, empty, or "local".
render_email() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check for error in cache
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    # Extract email
    local email
    email=$(printf '%s' "$cache_data" | jq -r '.account.email // empty')

    # Silent return if empty, null, or "local" placeholder
    [[ -z "$email" ]] && return 0
    [[ "$email" == "local" ]] && return 0

    # Truncate long emails (20 char max + ellipsis)
    if [[ ${#email} -gt 20 ]]; then
        email="${email:0:20}..."
    fi

    printf '#[fg=colour245]%s#[default]' "$email"
}
