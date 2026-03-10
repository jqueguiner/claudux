#!/usr/bin/env bash
# local_parse.sh — Claude Code JSONL session log parser for claudux tmux plugin
# Parses local session logs to aggregate token usage by time window and model.
# Outputs normalized JSON to stdout. Does NOT write to cache directly.
#
# JSONL schema is undocumented and may change. Fields verified 2026-03-10.
# Only "assistant" type entries contain model + usage data.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# _get_plan_limits — Return approximate token limits per plan tier
# Parameters: $1 = plan type (free, pro, max_5x, max_20x)
# Outputs: "weekly_limit monthly_limit" space-separated
# Approximate limits -- actual values may differ. Update as Anthropic publishes official numbers.
_get_plan_limits() {
    local plan_type="$1"
    local weekly_limit monthly_limit

    case "$plan_type" in
        free)
            weekly_limit=500000
            monthly_limit=2000000
            ;;
        pro)
            weekly_limit=5000000
            monthly_limit=20000000
            ;;
        max_5x)
            weekly_limit=25000000
            monthly_limit=100000000
            ;;
        max_20x)
            weekly_limit=100000000
            monthly_limit=400000000
            ;;
        *)
            # Default to max_5x if plan type unknown
            weekly_limit=25000000
            monthly_limit=100000000
            ;;
    esac

    printf '%s %s' "$weekly_limit" "$monthly_limit"
}

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
    local claude_dir="$HOME/.claude/projects"
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

    # Get plan type and limits
    local plan_type
    plan_type=$(get_tmux_option "@claudux_plan" "max_5x")
    local weekly_limit monthly_limit
    read -r weekly_limit monthly_limit <<< "$(_get_plan_limits "$plan_type")"

    # Get cutoff epochs
    local cutoff_7d cutoff_30d
    cutoff_7d=$(_get_cutoff_epoch 7)
    cutoff_30d=$(_get_cutoff_epoch 30)

    # Find session files
    local session_files
    session_files=$(_find_session_files)
    if [[ $? -ne 0 ]] || [[ -z "$session_files" ]]; then
        printf '{"mode":"local","fetched_at":%d,"account":{"email":"local"},"weekly":{"used":0,"limit":100,"unit":"percent","reset_at":0},"monthly":{"used":0,"limit":100,"unit":"percent","reset_at":0},"models":{},"error":{"code":"no_logs","message":"No Claude Code session logs found at ~/.claude/projects/"}}' "$now"
        return 1
    fi

    # Initialize accumulators
    local total_tokens_7d=0
    local total_tokens_30d=0
    local sonnet_tokens=0
    local opus_tokens=0
    local haiku_tokens=0

    # Process each JSONL file using optimized single-jq-pass approach
    local file
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        # Single jq pass extracts all assistant entries with model and usage data
        # Output as TSV: timestamp model input_tokens output_tokens
        jq -r 'select(.type == "assistant" and .message.model != null and .timestamp != null) |
            [.timestamp, .message.model,
             (.message.usage.input_tokens // 0),
             (.message.usage.output_tokens // 0)] |
            @tsv' "$file" 2>/dev/null |
        while IFS=$'\t' read -r timestamp_str model input_tokens output_tokens; do
            [[ -z "$timestamp_str" ]] && continue
            [[ -z "$model" ]] && continue

            local entry_epoch
            entry_epoch=$(_iso_to_epoch "$timestamp_str")
            [[ "$entry_epoch" -eq 0 ]] && continue

            local tokens=$(( input_tokens + output_tokens ))
            local normalized_model
            normalized_model=$(_normalize_model "$model")

            # Aggregate into 30-day window (includes 7-day)
            if [[ "$entry_epoch" -ge "$cutoff_30d" ]]; then
                total_tokens_30d=$(( total_tokens_30d + tokens ))

                # Per-model accumulation
                case "$normalized_model" in
                    sonnet) sonnet_tokens=$(( sonnet_tokens + tokens )) ;;
                    opus)   opus_tokens=$(( opus_tokens + tokens )) ;;
                    haiku)  haiku_tokens=$(( haiku_tokens + tokens )) ;;
                esac
            fi

            # Aggregate into 7-day window
            if [[ "$entry_epoch" -ge "$cutoff_7d" ]]; then
                total_tokens_7d=$(( total_tokens_7d + tokens ))
            fi
        done
    done <<< "$session_files"

    # Note: The while-read in a pipeline creates a subshell, so accumulator
    # variables won't be visible here. We need a different approach.
    # Use temp files to accumulate across subshell boundaries.

    # Re-implement with temp file accumulation
    local tmp_dir
    tmp_dir=$(mktemp -d) || {
        printf '{"mode":"local","fetched_at":%d,"account":{"email":"local"},"weekly":{"used":0,"limit":100,"unit":"percent","reset_at":0},"monthly":{"used":0,"limit":100,"unit":"percent","reset_at":0},"models":{},"error":{"code":"parse_failed","message":"Failed to create temp directory"}}' "$now"
        return 1
    }
    trap 'rm -rf "$tmp_dir"' RETURN

    # Initialize counter files
    printf '0' > "$tmp_dir/tokens_7d"
    printf '0' > "$tmp_dir/tokens_30d"
    printf '0' > "$tmp_dir/sonnet"
    printf '0' > "$tmp_dir/opus"
    printf '0' > "$tmp_dir/haiku"

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        # Single jq pass per file — extract all assistant entries as TSV
        local tsv_output
        tsv_output=$(jq -r 'select(.type == "assistant" and .message.model != null and .timestamp != null) |
            [.timestamp, .message.model,
             (.message.usage.input_tokens // 0),
             (.message.usage.output_tokens // 0)] |
            @tsv' "$file" 2>/dev/null) || continue

        [[ -z "$tsv_output" ]] && continue

        while IFS=$'\t' read -r timestamp_str model input_tokens output_tokens; do
            [[ -z "$timestamp_str" ]] && continue
            [[ -z "$model" ]] && continue

            local entry_epoch
            entry_epoch=$(_iso_to_epoch "$timestamp_str")
            [[ "$entry_epoch" -eq 0 ]] && continue

            local tokens=$(( input_tokens + output_tokens ))

            # 30-day window
            if [[ "$entry_epoch" -ge "$cutoff_30d" ]]; then
                local cur_30d
                cur_30d=$(cat "$tmp_dir/tokens_30d")
                printf '%s' "$(( cur_30d + tokens ))" > "$tmp_dir/tokens_30d"

                # Per-model
                local normalized_model
                normalized_model=$(_normalize_model "$model")
                case "$normalized_model" in
                    sonnet|opus|haiku)
                        local cur_model
                        cur_model=$(cat "$tmp_dir/$normalized_model")
                        printf '%s' "$(( cur_model + tokens ))" > "$tmp_dir/$normalized_model"
                        ;;
                esac
            fi

            # 7-day window
            if [[ "$entry_epoch" -ge "$cutoff_7d" ]]; then
                local cur_7d
                cur_7d=$(cat "$tmp_dir/tokens_7d")
                printf '%s' "$(( cur_7d + tokens ))" > "$tmp_dir/tokens_7d"
            fi
        done <<< "$tsv_output"
    done <<< "$session_files"

    # Read accumulated values
    total_tokens_7d=$(cat "$tmp_dir/tokens_7d")
    total_tokens_30d=$(cat "$tmp_dir/tokens_30d")
    sonnet_tokens=$(cat "$tmp_dir/sonnet")
    opus_tokens=$(cat "$tmp_dir/opus")
    haiku_tokens=$(cat "$tmp_dir/haiku")

    # Calculate usage percentages
    local weekly_pct monthly_pct sonnet_pct opus_pct
    if [[ "$weekly_limit" -gt 0 ]]; then
        weekly_pct=$(echo "scale=1; $total_tokens_7d * 100 / $weekly_limit" | bc 2>/dev/null || echo "0")
    else
        weekly_pct="0"
    fi
    if [[ "$monthly_limit" -gt 0 ]]; then
        monthly_pct=$(echo "scale=1; $total_tokens_30d * 100 / $monthly_limit" | bc 2>/dev/null || echo "0")
    else
        monthly_pct="0"
    fi
    if [[ "$weekly_limit" -gt 0 ]]; then
        sonnet_pct=$(echo "scale=1; $sonnet_tokens * 100 / $weekly_limit" | bc 2>/dev/null || echo "0")
        opus_pct=$(echo "scale=1; $opus_tokens * 100 / $weekly_limit" | bc 2>/dev/null || echo "0")
    else
        sonnet_pct="0"
        opus_pct="0"
    fi

    # Try to find account email
    local email="local"
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        local settings_email
        settings_email=$(jq -r '.email // empty' "$HOME/.claude/settings.json" 2>/dev/null)
        [[ -n "$settings_email" ]] && email="$settings_email"
    fi

    # Build normalized JSON matching cache schema
    printf '{
  "mode": "local",
  "fetched_at": %d,
  "account": {"email": "%s"},
  "weekly": {"used": %s, "limit": 100, "unit": "percent", "reset_at": 0},
  "monthly": {"used": %s, "limit": 100, "unit": "percent", "reset_at": 0},
  "models": {
    "sonnet": {"used": %s, "limit": 100, "unit": "percent", "reset_at": 0},
    "opus": {"used": %s, "limit": 100, "unit": "percent", "reset_at": 0}
  },
  "error": null
}' "$now" "$email" "$weekly_pct" "$monthly_pct" "$sonnet_pct" "$opus_pct"
}
