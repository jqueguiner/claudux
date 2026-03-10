#!/usr/bin/env bash
# local_parse.sh — Claude Code JSONL session log parser for claudux tmux plugin
# Parses local session logs to aggregate token usage by time window and model.
# Outputs normalized JSON to stdout. Does NOT write to cache directly.
#
# JSONL schema is undocumented and may change. Fields verified 2026-03-10.
# Only "assistant" type entries contain model + usage data.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/profiles.sh"
source "$CURRENT_DIR/plan_detect.sh"

# _get_cutoff_epoch — Get epoch timestamp for N days ago
# Parameters: $1 = days back
# Outputs: epoch timestamp
_get_cutoff_epoch() {
    local days="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        date -u -v-"${days}d" +%s
    else
        date -u -d "${days} days ago" +%s
    fi
}

# _normalize_model — Extract model family from full identifier
# Parameters: $1 = full model string (e.g., "claude-opus-4-6")
# Outputs: normalized family name (opus, sonnet, haiku, other)
_normalize_model() {
    local model="$1"
    case "$model" in
        *opus*)   printf 'opus' ;;
        *sonnet*) printf 'sonnet' ;;
        *haiku*)  printf 'haiku' ;;
        *)        printf 'other' ;;
    esac
}

# _iso_to_epoch — Convert ISO 8601 timestamp to epoch seconds
# Parameters: $1 = ISO timestamp (e.g., "2026-03-06T14:49:00.971Z")
# Outputs: epoch seconds, or 0 on failure
_iso_to_epoch() {
    local ts="$1"
    # Strip milliseconds and trailing Z
    local clean
    clean=$(printf '%s' "$ts" | sed 's/\.[0-9]*Z$//' | sed 's/Z$//')

    local epoch
    if [[ "$(get_platform)" == "darwin" ]]; then
        epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null)
    else
        epoch=$(date -u -d "$clean" +%s 2>/dev/null)
    fi

    printf '%s' "${epoch:-0}"
}

# _find_session_files — Find all JSONL session files modified within last 30 days
# Outputs: file paths, one per line
# Returns: 1 if no files found
_find_session_files() {
    local claude_base
    claude_base=$(get_profile_claude_dir 2>/dev/null)
    [[ -z "$claude_base" ]] && claude_base="$HOME/.claude"
    local claude_dir="$claude_base/projects"
    local cutoff_30d
    cutoff_30d=$(_get_cutoff_epoch 30)

    if [[ ! -d "$claude_dir" ]]; then
        return 1
    fi

    local found=0

    # Find JSONL files in project directories (no sessions/ subdirectory)
    # Also check subagent directories
    local file
    for file in "$claude_dir"/*/*.jsonl "$claude_dir"/*/*/subagents/*.jsonl; do
        [[ -f "$file" ]] || continue

        # Filter by modification time to limit scan scope
        local mtime
        mtime=$(get_file_mtime "$file") || continue
        if [[ "$mtime" -ge "$cutoff_30d" ]]; then
            printf '%s\n' "$file"
            found=1
        fi
    done

    [[ "$found" -eq 1 ]] && return 0 || return 1
}

# parse_local_logs — Main parser. Aggregates token usage from JSONL session logs.
# Outputs: Normalized JSON matching cache schema to stdout
parse_local_logs() {
    local now
    now=$(date +%s)

    local cutoff_7d cutoff_30d
    cutoff_7d=$(_get_cutoff_epoch 7)
    cutoff_30d=$(_get_cutoff_epoch 30)

    local session_files
    session_files=$(_find_session_files)
    if [[ $? -ne 0 ]] || [[ -z "$session_files" ]]; then
        printf '{"mode":"local","fetched_at":%d,"account":{"email":"local"},"weekly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"monthly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"models":{},"error":{"code":"no_logs","message":"No Claude Code session logs found"}}' "$now"
        return 1
    fi

    local file_args=()
    while IFS= read -r file; do
        [[ -f "$file" ]] && file_args+=("$file")
    done <<< "$session_files"

    [[ ${#file_args[@]} -eq 0 ]] && {
        printf '{"mode":"local","fetched_at":%d,"account":{"email":"local"},"weekly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"monthly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"models":{},"error":{"code":"no_logs","message":"No session files"}}' "$now"
        return 1
    }

    local limits
    limits=$(get_plan_limits 2>/dev/null)
    local weekly_limit monthly_limit sonnet_limit opus_limit
    read -r weekly_limit monthly_limit sonnet_limit opus_limit <<< "$limits"
    weekly_limit=${weekly_limit:-0}
    monthly_limit=${monthly_limit:-0}
    sonnet_limit=${sonnet_limit:-0}
    opus_limit=${opus_limit:-0}

    local aggregated
    aggregated=$(cat "${file_args[@]}" | jq -s \
      --argjson cutoff_7d "$cutoff_7d" \
      --argjson cutoff_30d "$cutoff_30d" \
      --argjson now "$now" \
      --argjson wlim "$weekly_limit" \
      --argjson mlim "$monthly_limit" \
      --argjson slim "$sonnet_limit" \
      --argjson olim "$opus_limit" '
      [.[] | select(.type == "assistant" and .message.model != null and .timestamp != null) |
        {
          ts: (.timestamp | sub("\\.[0-9]*Z$"; "Z") | fromdate),
          model: .message.model,
          tokens: ((.message.usage.input_tokens // 0) + (.message.usage.output_tokens // 0))
        }
      ] |
      {
        tokens_7d: ([.[] | select(.ts >= $cutoff_7d) | .tokens] | add // 0),
        tokens_30d: ([.[] | select(.ts >= $cutoff_30d) | .tokens] | add // 0),
        tokens_7d_sonnet: ([.[] | select(.ts >= $cutoff_7d and (.model | test("sonnet"))) | .tokens] | add // 0),
        tokens_7d_opus: ([.[] | select(.ts >= $cutoff_7d and (.model | test("opus"))) | .tokens] | add // 0),
        sonnet: ([.[] | select(.ts >= $cutoff_30d and (.model | test("sonnet"))) | .tokens] | add // 0),
        opus: ([.[] | select(.ts >= $cutoff_30d and (.model | test("opus"))) | .tokens] | add // 0),
        tokens_1h: ([.[] | select(.ts >= ($now - 3600)) | .tokens] | add // 0),
        tokens_2h: ([.[] | select(.ts >= ($now - 7200)) | .tokens] | add // 0),
        tokens_24h: ([.[] | select(.ts >= ($now - 86400)) | .tokens] | add // 0)
      } |
      {
        mode: "local",
        fetched_at: $now,
        account: {email: "local"},
        weekly: {used: .tokens_7d, limit: $wlim, unit: "tokens", reset_at: 0},
        monthly: {used: .tokens_30d, limit: $mlim, unit: "tokens", reset_at: 0},
        models: {
          sonnet: {used: .sonnet, limit: $slim, unit: "tokens", reset_at: 0},
          opus: {used: .opus, limit: $olim, unit: "tokens", reset_at: 0}
        },
        cost: {
          weekly: ((.tokens_7d_sonnet * 9 + .tokens_7d_opus * 45) / 1000000 | . * 100 | floor | . / 100),
          monthly: ((.sonnet * 9 + .opus * 45) / 1000000 | . * 100 | floor | . / 100),
          currency: "USD",
          estimated: true
        },
        velocity: {
          tokens_1h: .tokens_1h,
          tokens_per_hour: (if .tokens_24h > 0 then (.tokens_24h / 24 | floor) else 0 end),
          trend: (if .tokens_1h > (.tokens_2h - .tokens_1h) then "up" elif .tokens_1h < (.tokens_2h - .tokens_1h) then "down" else "stable" end)
        },
        error: null
      }
    ' 2>/dev/null)

    if [[ -n "$aggregated" ]]; then
        local email="local"
        local claude_dir
        claude_dir=$(get_profile_claude_dir 2>/dev/null)
        if [[ -f "$claude_dir/settings.json" ]]; then
            local settings_email
            settings_email=$(jq -r '.email // empty' "$claude_dir/settings.json" 2>/dev/null)
            [[ -n "$settings_email" ]] && email="$settings_email"
        fi
        printf '%s' "$aggregated" | jq --arg email "$email" '.account.email = $email'
    else
        printf '{"mode":"local","fetched_at":%d,"account":{"email":"local"},"weekly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"monthly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"models":{},"error":{"code":"parse_failed","message":"jq aggregation failed"}}' "$now"
        return 1
    fi
}
