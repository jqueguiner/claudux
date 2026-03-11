#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/profiles.sh"

_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -c1-8
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -c1-8
    else
        cksum | cut -d' ' -f1
    fi
}

_PLAN_LIMITS_max_weekly=45000000
_PLAN_LIMITS_max_monthly=180000000
_PLAN_LIMITS_max_sonnet=180000000
_PLAN_LIMITS_max_opus=180000000
_PLAN_LIMITS_pro_weekly=15000000
_PLAN_LIMITS_pro_monthly=60000000
_PLAN_LIMITS_pro_sonnet=60000000
_PLAN_LIMITS_pro_opus=60000000
_PLAN_LIMITS_team_weekly=30000000
_PLAN_LIMITS_team_monthly=120000000
_PLAN_LIMITS_team_sonnet=120000000
_PLAN_LIMITS_team_opus=120000000
_PLAN_LIMITS_enterprise_weekly=60000000
_PLAN_LIMITS_enterprise_monthly=240000000
_PLAN_LIMITS_enterprise_sonnet=240000000
_PLAN_LIMITS_enterprise_opus=240000000
_PLAN_LIMITS_free_weekly=5000000
_PLAN_LIMITS_free_monthly=20000000
_PLAN_LIMITS_free_sonnet=20000000
_PLAN_LIMITS_free_opus=20000000

_read_subscription_type() {
    local claude_dir
    claude_dir=$(get_profile_claude_dir 2>/dev/null)
    [[ -z "$claude_dir" ]] && claude_dir="$HOME/.claude"

    if [[ "$(get_platform)" == "darwin" ]] && command -v security >/dev/null 2>&1; then
        local config_hash=""
        if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
            config_hash="-$(printf '%s' "$claude_dir" | _sha256)"
        fi
        local service_name="Claude Code-credentials${config_hash}"

        local creds
        creds=$(security find-generic-password -a "$USER" -s "$service_name" -w 2>/dev/null) || {
            _try_credentials_file "$claude_dir"
            return
        }
        printf '%s' "$creds" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for key in ('claudeAiOauth', 'oauth'):
        if key in d and 'subscriptionType' in d[key]:
            print(d[key]['subscriptionType'])
            sys.exit(0)
except: pass
" 2>/dev/null
    else
        _try_credentials_file "$claude_dir"
    fi
}

_try_credentials_file() {
    local claude_dir="$1"
    local creds_file="$claude_dir/.credentials.json"
    [[ ! -f "$creds_file" ]] && return
    python3 -c "
import sys, json
try:
    with open('$creds_file') as f:
        d = json.load(f)
    for key in ('claudeAiOauth', 'oauth'):
        if key in d and 'subscriptionType' in d[key]:
            print(d[key]['subscriptionType'])
            sys.exit(0)
except: pass
" 2>/dev/null
}

_try_profile_api() {
    local claude_dir
    claude_dir=$(get_profile_claude_dir 2>/dev/null)
    [[ -z "$claude_dir" ]] && claude_dir="$HOME/.claude"

    local creds=""

    if [[ "$(get_platform)" == "darwin" ]] && command -v security >/dev/null 2>&1; then
        local config_hash=""
        if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
            config_hash="-$(printf '%s' "$claude_dir" | _sha256)"
        fi
        local service_name="Claude Code-credentials${config_hash}"
        creds=$(security find-generic-password -a "$USER" -s "$service_name" -w 2>/dev/null) || true
    fi

    if [[ -z "$creds" ]]; then
        local creds_file="$claude_dir/.credentials.json"
        [[ -f "$creds_file" ]] || return
        creds=$(cat "$creds_file" 2>/dev/null) || return
    fi

    local token
    token=$(printf '%s' "$creds" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for key in ('claudeAiOauth', 'oauth'):
        if key in d and 'accessToken' in d[key]:
            print(d[key]['accessToken'])
            sys.exit(0)
except: pass
" 2>/dev/null)

    [[ -z "$token" ]] && return

    local response
    response=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/profile" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" 2>/dev/null)

    local org_type
    org_type=$(printf '%s' "$response" | jq -r '.organization.organization_type // empty' 2>/dev/null)
    case "$org_type" in
        claude_max)        echo "max" ;;
        claude_pro)        echo "pro" ;;
        claude_enterprise) echo "enterprise" ;;
        claude_team)       echo "team" ;;
        *)                 return ;;
    esac
}

detect_plan() {
    local cache_dir
    cache_dir="$(get_cache_dir 2>/dev/null)" || cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
    local plan_cache="$cache_dir/plan.txt"
    local plan_cache_ttl=3600

    if [[ -f "$plan_cache" ]]; then
        local mtime now age
        mtime=$(get_file_mtime "$plan_cache") || mtime=0
        now=$(date +%s)
        age=$(( now - mtime ))
        if [[ $age -lt $plan_cache_ttl ]]; then
            cat "$plan_cache"
            return
        fi
    fi

    local plan
    plan=$(_read_subscription_type)

    if [[ -z "$plan" ]]; then
        plan=$(_try_profile_api)
    fi

    [[ -z "$plan" ]] && plan="max"

    mkdir -p "$(dirname "$plan_cache")" 2>/dev/null
    printf '%s' "$plan" > "$plan_cache"
    echo "$plan"
}

get_plan_limits() {
    local plan
    plan=$(detect_plan 2>/dev/null)
    [[ -z "$plan" ]] && plan="max"

    local weekly_var="_PLAN_LIMITS_${plan}_weekly"
    local monthly_var="_PLAN_LIMITS_${plan}_monthly"
    local sonnet_var="_PLAN_LIMITS_${plan}_sonnet"
    local opus_var="_PLAN_LIMITS_${plan}_opus"

    local weekly="${!weekly_var:-$_PLAN_LIMITS_max_weekly}"
    local monthly="${!monthly_var:-$_PLAN_LIMITS_max_monthly}"
    local sonnet="${!sonnet_var:-0}"
    local opus="${!opus_var:-0}"

    printf '%d %d %d %d' "$weekly" "$monthly" "$sonnet" "$opus"
}
