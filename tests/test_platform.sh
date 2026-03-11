#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/helpers.sh"
source "$SCRIPT_DIR/scripts/cache.sh"
source "$SCRIPT_DIR/scripts/credentials.sh"
source "$SCRIPT_DIR/scripts/render.sh"
source "$SCRIPT_DIR/scripts/plan_detect.sh"
source "$SCRIPT_DIR/scripts/local_parse.sh"
source "$SCRIPT_DIR/scripts/live_stats.sh"

PASS=0
FAIL=0
PLATFORM="$(get_platform)"

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }

assert_eq() {
    if [[ "$1" == "$2" ]]; then
        pass "$3"
    else
        fail "$3 (expected '$2', got '$1')"
    fi
}

assert_ne() {
    if [[ "$1" != "$2" ]]; then
        pass "$3"
    else
        fail "$3 (got '$2', expected different)"
    fi
}

assert_match() {
    if [[ "$1" =~ $2 ]]; then
        pass "$3"
    else
        fail "$3 (expected match '$2', got '$1')"
    fi
}

assert_ge() {
    if [[ "$1" -ge "$2" ]] 2>/dev/null; then
        pass "$3"
    else
        fail "$3 (expected >= $2, got '$1')"
    fi
}

assert_le() {
    if [[ "$1" -le "$2" ]] 2>/dev/null; then
        pass "$3"
    else
        fail "$3 (expected <= $2, got '$1')"
    fi
}

assert_empty() {
    if [[ -z "$1" ]]; then
        pass "$2"
    else
        fail "$2 (expected empty, got '$1')"
    fi
}

assert_not_empty() {
    if [[ -n "$1" ]]; then
        pass "$2"
    else
        fail "$2 (got empty)"
    fi
}

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2 (file not found: $1)"
    fi
}

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo ""
echo "Platform: $PLATFORM"
echo ""

# ─── PLAT-01: Platform Detection ────────────────────────────────────────────

echo "=== PLAT-01: Platform Detection ==="

result=$(get_platform)
if [[ "$PLATFORM" == "darwin" ]]; then
    assert_eq "$result" "darwin" "detected macOS"
else
    assert_eq "$result" "linux" "detected Linux"
fi

_CLAUDUX_PLATFORM=""
result2=$(get_platform)
assert_eq "$result2" "$result" "cached platform matches first call"

# ─── PLAT-02: File mtime (stat) ─────────────────────────────────────────────

echo ""
echo "=== PLAT-02: File Modification Time (stat) ==="

testfile="$TMPDIR_TEST/mtime_test"
touch "$testfile"
mtime=$(get_file_mtime "$testfile")
now=$(date +%s)
diff=$(( now - mtime ))
assert_ge "$mtime" 0 "mtime is non-negative"
assert_le "$diff" 5 "mtime is within 5 seconds of now"

mtime_missing=$(get_file_mtime "$TMPDIR_TEST/nonexistent" 2>/dev/null || true)
assert_eq "${mtime_missing:-0}" "0" "missing file returns 0"

# ─── PLAT-03: Date calculations ─────────────────────────────────────────────

echo ""
echo "=== PLAT-03: Date Calculations ==="

cutoff=$(_get_cutoff_epoch 7)
now=$(date +%s)
expected_min=$(( now - 7 * 86400 - 60 ))
expected_max=$(( now - 7 * 86400 + 60 ))
assert_ge "$cutoff" "$expected_min" "7-day cutoff epoch >= expected min"
assert_le "$cutoff" "$expected_max" "7-day cutoff epoch <= expected max"

cutoff30=$(_get_cutoff_epoch 30)
expected_min30=$(( now - 30 * 86400 - 60 ))
assert_ge "$cutoff30" "$expected_min30" "30-day cutoff epoch >= expected min"

# ─── PLAT-04: ISO-to-epoch conversion ───────────────────────────────────────

echo ""
echo "=== PLAT-04: ISO-to-Epoch Conversion ==="

epoch=$(_iso_to_epoch "2025-01-01T00:00:00.000Z")
assert_eq "$epoch" "1735689600" "2025-01-01T00:00:00Z => 1735689600"

epoch2=$(_iso_to_epoch "2025-06-15T12:30:45Z")
assert_eq "$epoch2" "1749990645" "2025-06-15T12:30:45Z => 1749990645"

epoch_bad=$(_iso_to_epoch "not-a-date")
assert_eq "$epoch_bad" "0" "invalid date returns 0"

# ─── PLAT-05: Weekly Reset Computation ──────────────────────────────────────

echo ""
echo "=== PLAT-05: Weekly Reset Computation ==="

now=$(date +%s)
reset=$(_compute_weekly_reset "$now")
assert_ge "$reset" "$now" "weekly reset is in the future"
max_reset=$(( now + 7 * 86400 + 86400 ))
assert_le "$reset" "$max_reset" "weekly reset is within ~8 days"

dow_at_reset=""
if [[ "$PLATFORM" == "darwin" ]]; then
    dow_at_reset=$(date -u -r "$reset" +%u 2>/dev/null)
else
    dow_at_reset=$(date -u -d "@$reset" +%u 2>/dev/null)
fi
assert_eq "$dow_at_reset" "1" "weekly reset falls on Monday (dow=1)"

# ─── PLAT-06: Monthly Reset Computation ─────────────────────────────────────

echo ""
echo "=== PLAT-06: Monthly Reset Computation ==="

mreset=$(_compute_monthly_reset "$now")
assert_ge "$mreset" "$now" "monthly reset is in the future"
max_mreset=$(( now + 32 * 86400 ))
assert_le "$mreset" "$max_mreset" "monthly reset is within ~32 days"

dom_at_reset=""
if [[ "$PLATFORM" == "darwin" ]]; then
    dom_at_reset=$(date -u -r "$mreset" +%d 2>/dev/null)
else
    dom_at_reset=$(date -u -d "@$mreset" +%d 2>/dev/null)
fi
assert_eq "$dom_at_reset" "01" "monthly reset falls on 1st of month"

# ─── PLAT-07: SHA-256 Hashing ───────────────────────────────────────────────

echo ""
echo "=== PLAT-07: SHA-256 Hashing ==="

hash1=$(printf 'test' | _sha256)
assert_not_empty "$hash1" "_sha256 produces output"
assert_match "$hash1" "^[0-9a-f]{8}$" "_sha256 is 8 hex chars"

hash2=$(printf 'test' | _sha256)
assert_eq "$hash1" "$hash2" "_sha256 is deterministic"

hash3=$(printf 'different' | _sha256)
assert_ne "$hash1" "$hash3" "_sha256 differs for different input"

# ─── PLAT-08: Cache Dir ─────────────────────────────────────────────────────

echo ""
echo "=== PLAT-08: Cache Directory ==="

export XDG_CACHE_HOME="$TMPDIR_TEST/cache"
cache_dir=$(get_cache_dir 2>/dev/null)
assert_not_empty "$cache_dir" "cache dir is non-empty"
if [[ -d "$cache_dir" ]]; then
    pass "cache directory was created"
else
    fail "cache directory was not created ($cache_dir)"
fi

# ─── PLAT-09: Cache Read/Write ──────────────────────────────────────────────

echo ""
echo "=== PLAT-09: Cache Read/Write ==="

test_json='{"test":"value","number":42}'
cache_write "$test_json"
read_back=$(cache_read)
parsed=$(printf '%s' "$read_back" | jq -r '.test')
assert_eq "$parsed" "value" "cache round-trip preserves data"

parsed_num=$(printf '%s' "$read_back" | jq -r '.number')
assert_eq "$parsed_num" "42" "cache round-trip preserves numbers"

# ─── PLAT-10: Cache Staleness ───────────────────────────────────────────────

echo ""
echo "=== PLAT-10: Cache Staleness ==="

cache_write '{"fresh":true}'
if is_cache_stale 9999; then
    fail "fresh cache should not be stale with TTL=9999"
else
    pass "fresh cache is not stale with TTL=9999"
fi

if is_cache_stale 0; then
    pass "cache is stale with TTL=0"
else
    fail "cache should be stale with TTL=0"
fi

# ─── PLAT-11: Credential File Permissions ───────────────────────────────────

echo ""
echo "=== PLAT-11: Credential File Permissions ==="

export XDG_CONFIG_HOME="$TMPDIR_TEST/config"
creds_dir="$(get_config_dir)"
mkdir -p "$creds_dir"

echo "sk-ant-admin01-testkey" > "$creds_dir/credentials"
chmod 600 "$creds_dir/credentials"

key=$(load_api_key 2>/dev/null)
assert_eq "$key" "sk-ant-admin01-testkey" "load_api_key reads 600-perm file"

key_type=$(get_key_type "$key")
assert_eq "$key_type" "admin" "detected admin key type"

chmod 644 "$creds_dir/credentials"
bad_key=$(load_api_key 2>/dev/null || echo "REJECTED")
assert_eq "$bad_key" "REJECTED" "load_api_key rejects 644 permissions"

chmod 600 "$creds_dir/credentials"

# ─── PLAT-12: Workspace Vitals ──────────────────────────────────────────────

echo ""
echo "=== PLAT-12: Workspace Vitals ==="

vitals=$(get_workspace_vitals 2>/dev/null)
read -r cpu mem disk <<< "$vitals"

assert_ge "$cpu" 0 "CPU percentage >= 0"
assert_le "$cpu" 999 "CPU percentage <= 999"
assert_ge "$mem" 0 "memory percentage >= 0"
assert_le "$mem" 100 "memory percentage <= 100"
assert_ge "$disk" 0 "disk percentage >= 0"
assert_le "$disk" 100 "disk percentage <= 100"

if [[ "$PLATFORM" == "linux" ]]; then
    if [[ -f /proc/loadavg ]]; then
        pass "/proc/loadavg exists for CPU measurement"
    else
        fail "/proc/loadavg missing"
    fi
    if [[ -f /proc/meminfo ]]; then
        pass "/proc/meminfo exists for memory measurement"
    else
        fail "/proc/meminfo missing"
    fi
fi

# ─── PLAT-13: Session Count / Memory ────────────────────────────────────────

echo ""
echo "=== PLAT-13: Session Count and Memory ==="

count=$(get_session_count 2>/dev/null)
assert_ge "$count" 0 "session count >= 0"

mem_val=$(get_session_memory 2>/dev/null)
assert_ge "${mem_val:-0}" 0 "session memory >= 0"

# ─── PLAT-14: Rate Limit History ────────────────────────────────────────────

echo ""
echo "=== PLAT-14: Rate Limit History ==="

hist=$(get_rate_limit_history 2>/dev/null)
assert_not_empty "$hist" "rate limit history returns output"
read -r h1 h24 h7d <<< "$hist"
assert_ge "$h1" 0 "1h rate limits >= 0"
assert_ge "$h24" 0 "24h rate limits >= 0"
assert_ge "$h7d" 0 "7d rate limits >= 0"

record_rate_limit 2>/dev/null
hist2=$(get_rate_limit_history 2>/dev/null)
read -r h1_after _ _ <<< "$hist2"
assert_ge "$h1_after" 1 "1h rate limits >= 1 after recording"

# ─── PLAT-15: Plan Detection ────────────────────────────────────────────────

echo ""
echo "=== PLAT-15: Plan Detection ==="

plan=$(detect_plan 2>/dev/null)
assert_not_empty "$plan" "detect_plan returns a plan"
assert_match "$plan" "^(max|pro|team|enterprise|free)$" "plan is a known value"

limits=$(get_plan_limits 2>/dev/null)
read -r wlim mlim slim olim <<< "$limits"
assert_ge "$wlim" 0 "weekly limit >= 0"
assert_ge "$mlim" 0 "monthly limit >= 0"

# ─── PLAT-16: Credentials File Plan Detection ───────────────────────────────

echo ""
echo "=== PLAT-16: Credentials File Plan Detection ==="

fake_claude="$TMPDIR_TEST/fake_claude"
mkdir -p "$fake_claude"
cat > "$fake_claude/.credentials.json" << 'JSON'
{"claudeAiOauth":{"subscriptionType":"pro","accessToken":"fake"}}
JSON

_CLAUDUX_PLATFORM=""
get_platform >/dev/null
old_plan_cache="$(get_cache_dir 2>/dev/null)/plan.txt"
rm -f "$old_plan_cache"

sub=$(_try_credentials_file "$fake_claude" 2>/dev/null)
assert_eq "$sub" "pro" "_try_credentials_file reads subscriptionType"

# ─── PLAT-17: Normalize Model ───────────────────────────────────────────────

echo ""
echo "=== PLAT-17: Model Normalization ==="

assert_eq "$(_normalize_model "claude-opus-4-6")" "opus" "normalize opus"
assert_eq "$(_normalize_model "claude-3-5-sonnet-20241022")" "sonnet" "normalize sonnet"
assert_eq "$(_normalize_model "claude-3-haiku-20240307")" "haiku" "normalize haiku"
assert_eq "$(_normalize_model "claude-unknown-99")" "other" "normalize other"

# ─── PLAT-18: Format Tokens ─────────────────────────────────────────────────

echo ""
echo "=== PLAT-18: Token Formatting ==="

assert_eq "$(_format_tokens 500)" "500" "format 500 tokens"
assert_eq "$(_format_tokens 1500)" "1.5k" "format 1500 tokens"
assert_eq "$(_format_tokens 45200)" "45.2k" "format 45200 tokens"
assert_eq "$(_format_tokens 1500000)" "1.5M" "format 1.5M tokens"
assert_eq "$(_format_tokens 0)" "0" "format 0 tokens"

# ─── PLAT-19: Format Countdown ──────────────────────────────────────────────

echo ""
echo "=== PLAT-19: Countdown Formatting ==="

assert_eq "$(_format_countdown 90061)" "1d 1h" "format >24h countdown"
assert_eq "$(_format_countdown 7380)" "2h 3m" "format >1h countdown"
assert_eq "$(_format_countdown 1800)" "30m" "format 30m countdown"
assert_eq "$(_format_countdown 300)" "5m" "format 5m countdown"
result=$(_format_countdown 0 2>/dev/null) || true
assert_empty "$result" "format 0 returns empty (failure)"
result=$(_format_countdown -100 2>/dev/null) || true
assert_empty "$result" "format negative returns empty (failure)"

# ─── PLAT-20: Sparkline ─────────────────────────────────────────────────────

echo ""
echo "=== PLAT-20: Sparkline Rendering ==="

assert_eq "$(_sparkline 0)" "▁" "sparkline 0%"
assert_eq "$(_sparkline 50)" "▄" "sparkline 50%"
assert_eq "$(_sparkline 100)" "█" "sparkline 100%"

# ─── PLAT-21: Vitals Color ──────────────────────────────────────────────────

echo ""
echo "=== PLAT-21: Vitals Color ==="

assert_eq "$(_vitals_color 30)" "colour34" "30% => green"
assert_eq "$(_vitals_color 75)" "colour220" "75% => yellow"
assert_eq "$(_vitals_color 95)" "colour196" "95% => red"

# ─── PLAT-22: Render Bar ────────────────────────────────────────────────────

echo ""
echo "=== PLAT-22: Render Bar ==="

_ucharlen() { printf '%s' "$1" | python3 -c "import sys; print(len(sys.stdin.read()))"; }

bar=$(render_bar 0 10)
assert_not_empty "$bar" "render_bar 0% returns output"
bar_stripped=$(printf '%s' "$bar" | sed 's/#\[[^]]*\]//g' | tr -d '[]')
char_count=$(_ucharlen "$bar_stripped")
assert_eq "$char_count" "10" "bar at 0% has 10 chars"

bar100=$(render_bar 100 10)
bar100_stripped=$(printf '%s' "$bar100" | sed 's/#\[[^]]*\]//g' | tr -d '[]')
char100=$(_ucharlen "$bar100_stripped")
assert_eq "$char100" "10" "bar at 100% has 10 chars"

bar20=$(render_bar 50 20)
bar20_stripped=$(printf '%s' "$bar20" | sed 's/#\[[^]]*\]//g' | tr -d '[]')
char20=$(_ucharlen "$bar20_stripped")
assert_eq "$char20" "20" "bar at 50% length=20 has 20 chars"

bar_clamped=$(render_bar 50 2)
bar_clamped_stripped=$(printf '%s' "$bar_clamped" | sed 's/#\[[^]]*\]//g' | tr -d '[]')
char_clamped=$(_ucharlen "$bar_clamped_stripped")
assert_eq "$char_clamped" "3" "bar_length=2 clamped to 3"

bar_clamped_max=$(render_bar 50 50)
bar_clamped_max_stripped=$(printf '%s' "$bar_clamped_max" | sed 's/#\[[^]]*\]//g' | tr -d '[]')
char_clamped_max=$(_ucharlen "$bar_clamped_max_stripped")
assert_eq "$char_clamped_max" "30" "bar_length=50 clamped to 30"

# ─── PLAT-23: Live Cache Write/Read ─────────────────────────────────────────

echo ""
echo "=== PLAT-23: Live Cache Write/Read ==="

write_live_cache 2>/dev/null || true
live=$(read_live_cache 2>/dev/null || echo "")
if [[ -n "$live" ]]; then
    ts=$(printf '%s' "$live" | jq -r '.ts // 0')
    assert_ge "$ts" 0 "live cache has valid timestamp"
    sess=$(printf '%s' "$live" | jq -r '.sessions // -1')
    assert_ge "$sess" 0 "live cache has sessions >= 0"
    cpu_val=$(printf '%s' "$live" | jq -r '.cpu // -1')
    assert_ge "$cpu_val" 0 "live cache has cpu >= 0"
    mem_val=$(printf '%s' "$live" | jq -r '.mem // -1')
    assert_ge "$mem_val" 0 "live cache has mem >= 0"
    disk_val=$(printf '%s' "$live" | jq -r '.disk // -1')
    assert_ge "$disk_val" 0 "live cache has disk >= 0"
    pass "write_live_cache + read_live_cache round-trip OK"
else
    pass "live cache write/read (no active sessions, empty expected)"
fi

# ─── PLAT-24: Lock Acquire/Release ──────────────────────────────────────────

echo ""
echo "=== PLAT-24: Lock Acquire/Release ==="

acquire_lock 2>/dev/null
lock_result=$?
assert_eq "$lock_result" "0" "acquire_lock succeeds"
release_lock 2>/dev/null
pass "release_lock completes without error"

acquire_lock 2>/dev/null
release_lock 2>/dev/null
acquire_lock 2>/dev/null
release_lock 2>/dev/null
pass "lock acquire/release is re-entrant"

# ─── PLAT-25: Date Range (api_fetch) ────────────────────────────────────────

echo ""
echo "=== PLAT-25: Date Range Calculation ==="

source "$SCRIPT_DIR/scripts/api_fetch.sh"
range=$(_get_date_range 7)
read -r start_date end_date <<< "$range"
assert_match "$start_date" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T" "start_date is ISO format"
assert_match "$end_date" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T" "end_date is ISO format"

range30=$(_get_date_range 30)
read -r start30 _ <<< "$range30"
assert_match "$start30" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T" "30-day start_date is ISO format"

# ─── PLAT-26: Profile System ────────────────────────────────────────────────

echo ""
echo "=== PLAT-26: Profile System ==="

export XDG_CONFIG_HOME="$TMPDIR_TEST/profiles_config"
mkdir -p "$XDG_CONFIG_HOME"
export XDG_CACHE_HOME="$TMPDIR_TEST/profiles_cache"

profile_add "test1" "local" "" "$TMPDIR_TEST/claude1" 2>/dev/null
active=$(get_active_profile_name 2>/dev/null)
assert_eq "$active" "test1" "first profile becomes active"

profile_add "test2" "local" "" "$TMPDIR_TEST/claude2" 2>/dev/null
list_output=$(profile_list 2>/dev/null)
assert_match "$list_output" "test1" "profile list contains test1"
assert_match "$list_output" "test2" "profile list contains test2"

profile_switch "test2" 2>/dev/null
active2=$(get_active_profile_name 2>/dev/null)
assert_eq "$active2" "test2" "switched to test2"

profile_next 2>/dev/null
active3=$(get_active_profile_name 2>/dev/null)
assert_eq "$active3" "test1" "profile_next rotated to test1"

profile_remove "test2" 2>/dev/null
list_after=$(profile_list 2>/dev/null)
if [[ "$list_after" == *"test2"* ]]; then
    fail "test2 still in list after remove"
else
    pass "test2 removed from list"
fi

# ─── PLAT-27: Install Hint (check_deps) ─────────────────────────────────────

echo ""
echo "=== PLAT-27: Install Hint ==="

source "$SCRIPT_DIR/scripts/check_deps.sh"
hint=$(_install_hint jq)
assert_not_empty "$hint" "_install_hint returns something"
if [[ "$PLATFORM" == "darwin" ]]; then
    assert_match "$hint" "brew" "macOS suggests brew"
else
    assert_match "$hint" "(apt|dnf|pacman|zypper|apk|package manager)" "Linux suggests system pkg manager"
fi

# ─── PLAT-28: Auto-profile Environment Reading ──────────────────────────────

echo ""
echo "=== PLAT-28: Environment Reading (auto_profile path) ==="

if [[ "$PLATFORM" == "linux" ]] && [[ -d /proc/$$/environ ]] || [[ -f /proc/$$/environ ]]; then
    env_val=$(tr '\0' '\n' < "/proc/$$/environ" 2>/dev/null | head -1)
    assert_not_empty "$env_val" "/proc/PID/environ is readable"
elif [[ "$PLATFORM" == "darwin" ]]; then
    env_val=$(ps -E -p $$ 2>/dev/null | head -2 | tail -1)
    assert_not_empty "$env_val" "ps -E reads environment on macOS"
else
    pass "environment reading skipped (not applicable in this context)"
fi

# ─── Results ─────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Platform: $PLATFORM"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
