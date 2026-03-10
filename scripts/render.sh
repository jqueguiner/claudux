#!/usr/bin/env bash
# render.sh — Progress bar rendering for claudux tmux plugin
# Produces tmux-formatted strings with Unicode progress bars and color coding.
# Each render_* function outputs a self-contained segment for the status bar.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/profiles.sh"
source "$CURRENT_DIR/live_stats.sh"

# render_bar — Core progress bar renderer
# Parameters: $1 = percentage (integer 0-100), $2 = bar_length (default 10)
# Outputs: tmux-formatted progress bar string with color coding
# Example: [#[fg=colour34]█████#[default]░░░░░]
render_bar() {
    local pct="$1"
    local bar_length="${2:-10}"

    # Clamp bar_length to valid range (3-30)
    [[ $bar_length -lt 3 ]] 2>/dev/null && bar_length=3
    [[ $bar_length -gt 30 ]] 2>/dev/null && bar_length=30

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
        color="colour238"  # Dark grey
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

_label() {
    local compact="$1" verbose="$2"
    local mode
    mode=$(get_tmux_option "@claudux_label_mode" "$CLAUDUX_DEFAULT_LABEL_MODE")
    if [[ "$mode" == "compact" ]]; then
        printf '%s' "$compact"
    else
        printf '%s' "$verbose"
    fi
}

_format_tokens() {
    local tokens="$1"
    if [[ "$tokens" -ge 1000000 ]]; then
        local m=$(( tokens / 100000 ))
        printf '%d.%dM' "$(( m / 10 ))" "$(( m % 10 ))"
    elif [[ "$tokens" -ge 1000 ]]; then
        local k=$(( tokens / 100 ))
        printf '%d.%dk' "$(( k / 10 ))" "$(( k % 10 ))"
    else
        printf '%d' "$tokens"
    fi
}

_render_usage() {
    local label="$1" used="$2" limit="$3"

    if [[ "$limit" -gt 0 ]]; then
        local pct=$(( (used * 100) / limit ))
        [[ $pct -gt 100 ]] && pct=100
        [[ $pct -lt 0 ]] && pct=0
        local bar_length
        bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")
        printf '#[fg=black,bold]%s:#[default] %s %d%%' "$label" "$(render_bar "$pct" "$bar_length")" "$pct"
    else
        [[ "$used" -eq 0 ]] 2>/dev/null && return 0
        printf '#[fg=black,bold]%s:#[default] %s' "$label" "$(_format_tokens "$used")"
    fi
}

render_weekly() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.weekly.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.weekly.limit // 0 | floor')
    _render_usage "$(_label W Weekly)" "$used" "$limit"
}

render_monthly() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.monthly.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.monthly.limit // 0 | floor')
    _render_usage "$(_label M Monthly)" "$used" "$limit"
}

render_model_sonnet() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0
    printf '%s' "$cache_data" | jq -e '.models.sonnet' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.models.sonnet.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.models.sonnet.limit // 0 | floor')
    _render_usage "$(_label S Sonnet)" "$used" "$limit"
}

render_model_opus() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0
    printf '%s' "$cache_data" | jq -e '.models.opus' >/dev/null 2>&1 || return 0

    local used limit
    used=$(printf '%s' "$cache_data" | jq -r '.models.opus.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.models.opus.limit // 0 | floor')
    _render_usage "$(_label O Opus)" "$used" "$limit"
}

# render_reset — Render quota reset countdown
# Reads reset_at from cache weekly and monthly sections, picks nearest non-zero.
# Output: #[fg=colour245]R:#[default] 2h 15m
# Adaptive format: Xd Yh (>24h), Xh Ym (<24h), Xm (<1h)
# Returns 0 silently if both reset_at are 0/missing, or if reset is in the past.
_format_countdown() {
    local remaining="$1"
    [[ "$remaining" -le 0 ]] && return 1

    local days hours minutes
    days=$(( remaining / 86400 ))
    hours=$(( (remaining % 86400) / 3600 ))
    minutes=$(( (remaining % 3600) / 60 ))

    if [[ "$days" -gt 0 ]]; then
        printf '%dd %dh' "$days" "$hours"
    elif [[ "$hours" -gt 0 ]]; then
        printf '%dh %dm' "$hours" "$minutes"
    else
        [[ "$minutes" -le 0 ]] && minutes=1
        printf '%dm' "$minutes"
    fi
}

_compute_weekly_reset() {
    local now="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        local dow
        dow=$(date -u -r "$now" +%u)
        local days_until_monday=$(( (8 - dow) % 7 ))
        [[ "$days_until_monday" -eq 0 ]] && days_until_monday=7
        local today_midnight
        today_midnight=$(date -u -r "$now" +"%Y-%m-%dT00:00:00Z")
        local today_epoch
        today_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$today_midnight" +%s 2>/dev/null)
        echo $(( today_epoch + days_until_monday * 86400 ))
    else
        local dow
        dow=$(date -u -d "@$now" +%u)
        local days_until_monday=$(( (8 - dow) % 7 ))
        [[ "$days_until_monday" -eq 0 ]] && days_until_monday=7
        local today_midnight
        today_midnight=$(date -u -d "@$now" +"%Y-%m-%d 00:00:00")
        local today_epoch
        today_epoch=$(date -u -d "$today_midnight" +%s)
        echo $(( today_epoch + days_until_monday * 86400 ))
    fi
}

_compute_monthly_reset() {
    local now="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        local next_month
        next_month=$(date -u -r "$now" -v1d -v+1m +"%Y-%m-%dT00:00:00Z")
        date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$next_month" +%s 2>/dev/null
    else
        local next_month
        next_month=$(date -u -d "$(date -u -d "@$now" +%Y-%m-01) +1 month" +%s)
        echo "$next_month"
    fi
}

render_reset() {
    local cache_data
    cache_data=$(cache_read) || return 0

    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local weekly_reset monthly_reset
    weekly_reset=$(printf '%s' "$cache_data" | jq -r '.weekly.reset_at // 0')
    monthly_reset=$(printf '%s' "$cache_data" | jq -r '.monthly.reset_at // 0')

    local now
    now=$(date +%s)

    if [[ "$weekly_reset" -le 0 ]] 2>/dev/null; then
        weekly_reset=$(_compute_weekly_reset "$now")
    fi
    if [[ "$monthly_reset" -le 0 ]] 2>/dev/null; then
        monthly_reset=$(_compute_monthly_reset "$now")
    fi

    local output=""
    local w_remaining=$(( weekly_reset - now ))
    local w_str
    w_str=$(_format_countdown "$w_remaining")
    if [[ -n "$w_str" ]]; then
        output="#[fg=black,bold]$(_label RW "Reset Weekly"):#[default] ${w_str}"
    fi

    local m_remaining=$(( monthly_reset - now ))
    local m_str
    m_str=$(_format_countdown "$m_remaining")
    if [[ -n "$m_str" ]]; then
        [[ -n "$output" ]] && output="${output} "
        output="${output}#[fg=black,bold]$(_label RM "Reset Monthly"):#[default] ${m_str}"
    fi

    [[ -n "$output" ]] && printf '%s' "$output"
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

# render_stale_indicator — Indicate when cache data is stale
# Stale = cache file mtime > 2x refresh interval
# Output: #[fg=colour136]?#[default] (dim yellow question mark)
# Returns empty string if cache is fresh, missing, or threshold not exceeded
render_stale_indicator() {
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 0
    local cache_file="${cache_dir}/cache.json"

    # No cache file = nothing to mark as stale
    [[ ! -f "$cache_file" ]] && return 0

    # Get refresh interval (default 300 seconds = 5 min)
    local refresh_interval
    refresh_interval=$(get_tmux_option "@claudux_refresh_interval" "$CLAUDUX_DEFAULT_REFRESH_INTERVAL")

    # Stale threshold = 2x refresh interval
    local stale_threshold=$(( refresh_interval * 2 ))

    # Get cache file mtime
    local mtime
    mtime=$(get_file_mtime "$cache_file") || return 0

    # Calculate age
    local now age
    now=$(date +%s)
    age=$(( now - mtime ))

    # Output stale indicator if age exceeds threshold
    if [[ $age -ge $stale_threshold ]]; then
        printf '#[fg=colour136]?#[default]'
    fi
}

# render_error — Render error state indicator
# Reads cache error field. Outputs red [!] with error code.
# Output: #[fg=colour196][!] auth_failed#[default]
# Returns 0 silently if no error in cache or cache missing.
render_error() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check if error field exists and is non-null
    local error_code
    error_code=$(printf '%s' "$cache_data" | jq -r '.error.code // empty')
    [[ -z "$error_code" ]] && return 0

    printf '#[fg=colour196][!] %s#[default]' "$error_code"
}

render_cost() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0
    printf '%s' "$cache_data" | jq -e '.cost' >/dev/null 2>&1 || return 0

    local weekly monthly estimated
    weekly=$(printf '%s' "$cache_data" | jq -r '.cost.weekly // 0')
    monthly=$(printf '%s' "$cache_data" | jq -r '.cost.monthly // 0')
    estimated=$(printf '%s' "$cache_data" | jq -r '.cost.estimated // false')

    [[ "$weekly" == "0" ]] && [[ "$monthly" == "0" ]] && return 0

    local prefix=""
    [[ "$estimated" == "true" ]] && prefix="~"

    printf '#[fg=black,bold]%s:#[default] %s$%s #[fg=black,bold]%s:#[default] %s$%s' \
        "$(_label CW "Cost Weekly")" "$prefix" "$weekly" \
        "$(_label CM "Cost Monthly")" "$prefix" "$monthly"
}

render_velocity() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0
    printf '%s' "$cache_data" | jq -e '.velocity' >/dev/null 2>&1 || return 0

    local tph trend
    tph=$(printf '%s' "$cache_data" | jq -r '.velocity.tokens_per_hour // 0')
    trend=$(printf '%s' "$cache_data" | jq -r '.velocity.trend // "stable"')

    [[ "$tph" -eq 0 ]] 2>/dev/null && return 0

    local arrow
    case "$trend" in
        up)     arrow="#[fg=colour196]^#[default]" ;;
        down)   arrow="#[fg=colour34]v#[default]" ;;
        *)      arrow="#[fg=colour245]-#[default]" ;;
    esac

    local formatted
    formatted=$(_format_tokens "$tph")

    printf '#[fg=black,bold]%s:#[default] %s/h %s' "$(_label V Velocity)" "$formatted" "$arrow"
}

render_context() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local ctx
    ctx=$(printf '%s' "$live" | jq -r '.context // 0')
    [[ "$ctx" -eq 0 ]] 2>/dev/null && return 0

    local max_ctx=200000
    local pct=$(( (ctx * 100) / max_ctx ))
    [[ $pct -gt 100 ]] && pct=100
    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")
    printf '#[fg=black,bold]%s:#[default] %s %d%%' "$(_label CTX Context)" "$(render_bar "$pct" "$bar_length")" "$pct"
}

render_model() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local model
    model=$(printf '%s' "$live" | jq -r '.model // empty')
    [[ -z "$model" ]] && return 0

    local color
    case "$model" in
        opus)   color="colour135" ;;
        sonnet) color="colour39" ;;
        haiku)  color="colour214" ;;
        *)      color="colour245" ;;
    esac
    printf '#[fg=%s]●#[default] %s' "$color" "$model"
}

render_burn_rate() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit tph
    used=$(printf '%s' "$cache_data" | jq -r '.weekly.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.weekly.limit // 0 | floor')
    tph=$(printf '%s' "$cache_data" | jq -r '.velocity.tokens_per_hour // 0')

    [[ "$limit" -le 0 ]] && return 0
    [[ "$tph" -le 0 ]] && return 0

    local remaining=$(( limit - used ))
    [[ "$remaining" -le 0 ]] && {
        printf '#[fg=colour196]%s: depleted#[default]' "$(_label BR Burn)"
        return 0
    }
    local hours_left=$(( remaining / tph ))
    local formatted
    if [[ "$hours_left" -ge 24 ]]; then
        formatted="$(( hours_left / 24 ))d $(( hours_left % 24 ))h"
    elif [[ "$hours_left" -gt 0 ]]; then
        formatted="${hours_left}h"
    else
        formatted="<1h"
    fi
    printf '#[fg=black,bold]%s:#[default] ~%s left' "$(_label BR Burn)" "$formatted"
}

render_cooldown() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local rl
    rl=$(printf '%s' "$live" | jq -r '.rate_limit // "ok"')
    [[ "$rl" == "ok" ]] && return 0

    local info="${rl#limited:}"
    if [[ "$info" != "$rl" ]] && [[ -n "$info" ]]; then
        printf '#[fg=colour196]%s: %s#[default]' "$(_label CD Cooldown)" "$info"
    else
        printf '#[fg=colour196]%s: rate limited#[default]' "$(_label CD Cooldown)"
    fi
}

render_sessions() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local count mem
    count=$(printf '%s' "$live" | jq -r '.sessions // 0')
    mem=$(printf '%s' "$live" | jq -r '.memory_mb // 0')
    [[ "$count" -eq 0 ]] 2>/dev/null && return 0

    if [[ "$mem" -gt 0 ]] 2>/dev/null; then
        printf '#[fg=black,bold]%s:#[default] %s (%sMB)' "$(_label SS Sessions)" "$count" "$mem"
    else
        printf '#[fg=black,bold]%s:#[default] %s' "$(_label SS Sessions)" "$count"
    fi
}

render_heartbeat() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local count
    count=$(printf '%s' "$live" | jq -r '.sessions // 0')
    [[ "$count" -eq 0 ]] 2>/dev/null && return 0

    local ts
    ts=$(printf '%s' "$live" | jq -r '.ts // 0')
    local now
    now=$(date +%s)
    local age=$(( now - ts ))

    if [[ $age -lt 5 ]]; then
        printf '#[fg=colour34]●#[default]'
    elif [[ $age -lt 15 ]]; then
        printf '#[fg=colour220]●#[default]'
    else
        printf '#[fg=colour240]○#[default]'
    fi
}

render_rate_limit_history() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local h1 h24 h7d
    h1=$(printf '%s' "$live" | jq -r '.rl_1h // 0')
    h24=$(printf '%s' "$live" | jq -r '.rl_24h // 0')
    h7d=$(printf '%s' "$live" | jq -r '.rl_7d // 0')
    [[ "$h7d" -eq 0 ]] 2>/dev/null && return 0

    local color="colour34"
    [[ "$h24" -ge 3 ]] && color="colour220"
    [[ "$h24" -ge 6 ]] && color="colour196"

    printf '#[fg=black,bold]%s:#[default] #[fg=%s]%s#[default]/%s/%s' \
        "$(_label RL "Rate Limits")" "$color" "$h1" "$h24" "$h7d"
}

render_rate_limit_predictor() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    local used limit tph
    used=$(printf '%s' "$cache_data" | jq -r '.weekly.used // 0 | floor')
    limit=$(printf '%s' "$cache_data" | jq -r '.weekly.limit // 0 | floor')
    tph=$(printf '%s' "$cache_data" | jq -r '.velocity.tokens_per_hour // 0')

    [[ "$limit" -le 0 ]] && return 0
    [[ "$tph" -le 0 ]] && return 0

    local pct=$(( (used * 100) / limit ))
    [[ "$pct" -lt 70 ]] && return 0

    local remaining=$(( limit - used ))
    [[ "$remaining" -le 0 ]] && {
        printf '#[fg=colour196,bold]%s: NOW#[default]' "$(_label RL! "Rate Limit")"
        return 0
    }
    local hours_left=$(( remaining / tph ))
    local formatted
    if [[ "$hours_left" -ge 24 ]]; then
        formatted="$(( hours_left / 24 ))d $(( hours_left % 24 ))h"
    elif [[ "$hours_left" -gt 0 ]]; then
        formatted="${hours_left}h"
    else
        formatted="<1h"
    fi

    local color="colour220"
    [[ "$hours_left" -lt 6 ]] && color="colour196"

    printf '#[fg=%s]%s: ~%s#[default]' "$color" "$(_label RL! "Rate Limit")" "$formatted"
}

_sparkline() {
    local pct="$1"
    local bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
    local idx=$(( pct * 7 / 100 ))
    [[ $idx -gt 7 ]] && idx=7
    [[ $idx -lt 0 ]] && idx=0
    printf '%s' "${bars[$idx]}"
}

_vitals_color() {
    local pct="$1"
    if [[ "$pct" -ge 90 ]]; then
        printf 'colour196'
    elif [[ "$pct" -ge 70 ]]; then
        printf 'colour220'
    else
        printf 'colour34'
    fi
}

render_vitals() {
    local live
    live=$(read_live_cache 2>/dev/null) || return 0
    local cpu mem disk
    cpu=$(printf '%s' "$live" | jq -r '.cpu // 0')
    mem=$(printf '%s' "$live" | jq -r '.mem // 0')
    disk=$(printf '%s' "$live" | jq -r '.disk // 0')

    printf '#[fg=black,bold]%s:#[default] ' "$(_label SYS System)"
    printf '#[fg=%s]%s#[default]%d ' "$(_vitals_color "$cpu")" "$(_sparkline "$cpu")" "$cpu"
    printf '#[fg=%s]%s#[default]%d ' "$(_vitals_color "$mem")" "$(_sparkline "$mem")" "$mem"
    printf '#[fg=%s]%s#[default]%d' "$(_vitals_color "$disk")" "$(_sparkline "$disk")" "$disk"
}

render_profile() {
    local name
    name=$(get_active_profile_name 2>/dev/null)
    [[ -z "$name" ]] && return 0
    printf '#[fg=black,bold]%s:#[default] %s' "$(_label P Profile)" "$name"
}
