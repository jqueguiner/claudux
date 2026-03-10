#!/usr/bin/env bash
# api_fetch.sh — Anthropic Admin API client for claudux tmux plugin
# Fetches usage, cost, and organization data from the Admin API.
# Outputs normalized JSON to stdout. Does NOT write to cache directly.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# API base URL (overridable for testing)
CLAUDUX_API_BASE="${CLAUDUX_API_BASE:-https://api.anthropic.com}"

# _api_request — Internal function for all Admin API calls
# Parameters: $1 = full URL, $2 = API key
# Outputs: response body on success, error JSON on failure (to stderr)
# Returns: 0 on success, 1 on failure
_api_request() {
    local url="$1"
    local api_key="$2"
    local response http_code body

    response=$(curl -s -w "\n%{http_code}" \
        --connect-timeout 10 \
        --max-time 30 \
        -H "anthropic-version: 2023-06-01" \
        -H "x-api-key: $api_key" \
        "$url" 2>/dev/null)

    # Split response body and status code
    http_code=$(printf '%s' "$response" | tail -1)
    body=$(printf '%s' "$response" | sed '$d')

    case "$http_code" in
        200)
            printf '%s' "$body"
            return 0
            ;;
        401|403)
            printf '{"code":"auth_failed","message":"Invalid or insufficient API key"}' >&2
            return 1
            ;;
        429)
            printf '{"code":"rate_limited","message":"Rate limited -- increase refresh interval"}' >&2
            return 1
            ;;
        5[0-9][0-9])
            printf '{"code":"api_unavailable","message":"Anthropic API unavailable (HTTP %s)"}' "$http_code" >&2
            return 1
            ;;
        *)
            printf '{"code":"unknown","message":"Unexpected HTTP %s"}' "$http_code" >&2
            return 1
            ;;
    esac
}

# _get_date_range — Cross-platform date range calculation
# Parameters: $1 = days back (e.g., 7 or 30)
# Outputs: "start_rfc3339 end_rfc3339" space-separated
_get_date_range() {
    local days="$1"
    local start_date end_date

    end_date=$(date -u +"%Y-%m-%dT23:59:59Z")

    if [[ "$(get_platform)" == "darwin" ]]; then
        start_date=$(date -u -v-"${days}d" +"%Y-%m-%dT00:00:00Z")
    else
        start_date=$(date -u -d "${days} days ago" +"%Y-%m-%dT00:00:00Z")
    fi

    printf '%s %s' "$start_date" "$end_date"
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

# fetch_usage_report — Fetch token usage from Admin API
# Parameters: $1 = API key, $2 = days back (default: 7)
# Outputs: merged data array JSON to stdout
fetch_usage_report() {
    local api_key="$1"
    local days="${2:-7}"
    local start_date end_date
    read -r start_date end_date <<< "$(_get_date_range "$days")"

    local base_url="${CLAUDUX_API_BASE}/v1/organizations/usage_report/messages"
    local page_token=""
    local all_data="[]"

    while true; do
        local url="${base_url}?starting_at=${start_date}&ending_at=${end_date}&group_by[]=model&bucket_width=1d"
        [[ -n "$page_token" ]] && url="${url}&page=${page_token}"

        local result
        result=$(_api_request "$url" "$api_key") || return 1

        # Merge data arrays
        local new_data
        new_data=$(printf '%s' "$result" | jq '.data // []')
        all_data=$(printf '%s\n%s' "$all_data" "$new_data" | jq -s '.[0] + .[1]')

        # Check pagination
        local has_more
        has_more=$(printf '%s' "$result" | jq -r '.has_more // false')
        [[ "$has_more" != "true" ]] && break

        page_token=$(printf '%s' "$result" | jq -r '.next_page // empty')
        [[ -z "$page_token" ]] && break
    done

    printf '%s' "$all_data"
}

# fetch_cost_report — Fetch cost data from Admin API
# Parameters: $1 = API key, $2 = days back (default: 7)
# Outputs: merged data array JSON to stdout
fetch_cost_report() {
    local api_key="$1"
    local days="${2:-7}"
    local start_date end_date
    read -r start_date end_date <<< "$(_get_date_range "$days")"

    local base_url="${CLAUDUX_API_BASE}/v1/organizations/cost_report"
    local page_token=""
    local all_data="[]"

    while true; do
        local url="${base_url}?starting_at=${start_date}&ending_at=${end_date}&bucket_width=1d"
        [[ -n "$page_token" ]] && url="${url}&page=${page_token}"

        local result
        result=$(_api_request "$url" "$api_key") || return 1

        local new_data
        new_data=$(printf '%s' "$result" | jq '.data // []')
        all_data=$(printf '%s\n%s' "$all_data" "$new_data" | jq -s '.[0] + .[1]')

        local has_more
        has_more=$(printf '%s' "$result" | jq -r '.has_more // false')
        [[ "$has_more" != "true" ]] && break

        page_token=$(printf '%s' "$result" | jq -r '.next_page // empty')
        [[ -z "$page_token" ]] && break
    done

    printf '%s' "$all_data"
}

# fetch_org_info — Get organization name and first user email
# Parameters: $1 = API key
# Outputs: JSON with org_name and email
fetch_org_info() {
    local api_key="$1"
    local org_name="" email=""

    # Get organization name
    local org_result
    org_result=$(_api_request "${CLAUDUX_API_BASE}/v1/organizations/me" "$api_key" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$org_result" ]]; then
        org_name=$(printf '%s' "$org_result" | jq -r '.name // ""')
    fi

    # Get first member email
    local users_result
    users_result=$(_api_request "${CLAUDUX_API_BASE}/v1/organizations/users?limit=1" "$api_key" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$users_result" ]]; then
        email=$(printf '%s' "$users_result" | jq -r '.data[0].email // ""' 2>/dev/null)
    fi

    printf '{"org_name":"%s","email":"%s"}' "$org_name" "$email"
}

# api_fetch — Main entry point. Produces normalized cache JSON.
# Parameters: $1 = API key
# Outputs: Normalized JSON matching cache schema to stdout
api_fetch() {
    local api_key="$1"
    local now
    now=$(date +%s)

    # Fetch weekly usage (7 days)
    local weekly_data
    weekly_data=$(fetch_usage_report "$api_key" 7 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$weekly_data" ]]; then
        local err_code="${weekly_data:-unknown}"
        printf '{"mode":"org","fetched_at":%d,"account":{"email":""},"weekly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"monthly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"models":{},"error":{"code":"fetch_failed","message":"Failed to fetch weekly usage data"}}' "$now"
        return 1
    fi

    # Fetch monthly usage (30 days)
    local monthly_data
    monthly_data=$(fetch_usage_report "$api_key" 30 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$monthly_data" ]]; then
        printf '{"mode":"org","fetched_at":%d,"account":{"email":""},"weekly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"monthly":{"used":0,"limit":0,"unit":"tokens","reset_at":0},"models":{},"error":{"code":"fetch_failed","message":"Failed to fetch monthly usage data"}}' "$now"
        return 1
    fi

    # Fetch org info (non-critical -- continue if fails)
    local org_info email=""
    org_info=$(fetch_org_info "$api_key" 2>/dev/null)
    if [[ -n "$org_info" ]]; then
        email=$(printf '%s' "$org_info" | jq -r '.email // ""')
    fi

    # Sum tokens from weekly data across all time buckets and models
    # Each bucket has results[] with uncached_input_tokens, cache_read_input_tokens, output_tokens
    local weekly_total
    weekly_total=$(printf '%s' "$weekly_data" | jq '
        [.[].results[] |
            (.uncached_input_tokens // 0) +
            (.cache_read_input_tokens // 0) +
            (.output_tokens // 0)
        ] | add // 0
    ')

    # Sum tokens from monthly data
    local monthly_total
    monthly_total=$(printf '%s' "$monthly_data" | jq '
        [.[].results[] |
            (.uncached_input_tokens // 0) +
            (.cache_read_input_tokens // 0) +
            (.output_tokens // 0)
        ] | add // 0
    ')

    # Per-model token sums from weekly data (normalized to family names)
    # Group by model family and sum tokens
    local sonnet_tokens opus_tokens haiku_tokens
    sonnet_tokens=$(printf '%s' "$weekly_data" | jq '
        [.[].results[] | select(.model != null) |
            select(.model | test("sonnet"; "i")) |
            (.uncached_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0)
        ] | add // 0
    ')
    opus_tokens=$(printf '%s' "$weekly_data" | jq '
        [.[].results[] | select(.model != null) |
            select(.model | test("opus"; "i")) |
            (.uncached_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0)
        ] | add // 0
    ')
    haiku_tokens=$(printf '%s' "$weekly_data" | jq '
        [.[].results[] | select(.model != null) |
            select(.model | test("haiku"; "i")) |
            (.uncached_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0)
        ] | add // 0
    ')

    local weekly_cost=0 monthly_cost=0
    local cost_7d cost_30d
    cost_7d=$(fetch_cost_report "$api_key" 7 2>/dev/null)
    if [[ -n "$cost_7d" ]]; then
        weekly_cost=$(printf '%s' "$cost_7d" | jq '[.[].results[] | .cost_cents // 0] | add // 0 | . / 100' 2>/dev/null)
    fi
    cost_30d=$(fetch_cost_report "$api_key" 30 2>/dev/null)
    if [[ -n "$cost_30d" ]]; then
        monthly_cost=$(printf '%s' "$cost_30d" | jq '[.[].results[] | .cost_cents // 0] | add // 0 | . / 100' 2>/dev/null)
    fi
    [[ -z "$weekly_cost" ]] && weekly_cost=0
    [[ -z "$monthly_cost" ]] && monthly_cost=0

    printf '{
  "mode": "org",
  "fetched_at": %d,
  "account": {"email": "%s"},
  "weekly": {"used": %s, "limit": 0, "unit": "tokens", "reset_at": 0},
  "monthly": {"used": %s, "limit": 0, "unit": "tokens", "reset_at": 0},
  "models": {
    "sonnet": {"used": %s, "limit": 0, "unit": "tokens", "reset_at": 0},
    "opus": {"used": %s, "limit": 0, "unit": "tokens", "reset_at": 0}
  },
  "cost": {"weekly": %s, "monthly": %s, "currency": "USD"},
  "velocity": {"tokens_1h": 0, "tokens_per_hour": %s, "trend": "stable"},
  "error": null
}' "$now" "$email" "$weekly_total" "$monthly_total" "$sonnet_tokens" "$opus_tokens" "$weekly_cost" "$monthly_cost" "$(( weekly_total / 168 ))"
}
