#!/usr/bin/env bash
# test_config.sh — End-to-end tests for @claudux_* configuration options
# Tests CONF-01 (toggles), CONF-02 (thresholds), CONF-03 (refresh), CONF-05 (bar_length)
# Requires: tmux server running (tests read/write tmux options)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/helpers.sh"
source "$SCRIPT_DIR/scripts/cache.sh"
source "$SCRIPT_DIR/scripts/render.sh"

# ─── Check tmux server ──────────────────────────────────────────────────────

if ! tmux list-sessions &>/dev/null; then
    echo "SKIP: tmux server not running — tests require a tmux session"
    exit 0
fi

# ─── Test Framework ──────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
assert_empty() {
    if [[ -z "$1" ]]; then
        pass "$2"
    else
        fail "$2 (got: '$1')"
    fi
}
assert_not_empty() {
    if [[ -n "$1" ]]; then
        pass "$2"
    else
        fail "$2 (got empty)"
    fi
}
assert_contains() {
    if [[ "$1" == *"$2"* ]]; then
        pass "$3"
    else
        fail "$3 (expected '$2' in output)"
    fi
}
assert_not_contains() {
    if [[ "$1" != *"$2"* ]]; then
        pass "$3"
    else
        fail "$3 (unexpected '$2' found in output)"
    fi
}

# ─── Setup ───────────────────────────────────────────────────────────────────

setup_test_cache() {
    local now
    now=$(date +%s)
    cache_write "{
        \"weekly\": {\"used\": 50, \"limit\": 100, \"reset_at\": $((now + 7200))},
        \"monthly\": {\"used\": 200, \"limit\": 1000, \"reset_at\": $((now + 86400))},
        \"models\": {
            \"sonnet\": {\"used\": 30, \"limit\": 100},
            \"opus\": {\"used\": 10, \"limit\": 50}
        },
        \"account\": {\"email\": \"test@example.com\"},
        \"error\": null
    }"
}

teardown() {
    # Reset all tmux options to defaults
    set_tmux_option "@claudux_show_weekly" "$CLAUDUX_DEFAULT_SHOW_WEEKLY"
    set_tmux_option "@claudux_show_monthly" "$CLAUDUX_DEFAULT_SHOW_MONTHLY"
    set_tmux_option "@claudux_show_model" "$CLAUDUX_DEFAULT_SHOW_MODEL"
    set_tmux_option "@claudux_show_reset" "$CLAUDUX_DEFAULT_SHOW_RESET"
    set_tmux_option "@claudux_show_email" "$CLAUDUX_DEFAULT_SHOW_EMAIL"
    set_tmux_option "@claudux_warning_threshold" "$CLAUDUX_DEFAULT_WARNING_THRESHOLD"
    set_tmux_option "@claudux_critical_threshold" "$CLAUDUX_DEFAULT_CRITICAL_THRESHOLD"
    set_tmux_option "@claudux_refresh_interval" "$CLAUDUX_DEFAULT_REFRESH_INTERVAL"
    set_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH"
}
trap teardown EXIT

# Write test cache data
setup_test_cache

echo ""
echo "=== CONF-01: Toggle Tests ==="

# Weekly toggle
set_tmux_option "@claudux_show_weekly" "off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" weekly 2>/dev/null || true)
assert_empty "$output" "weekly hidden when show_weekly=off"

set_tmux_option "@claudux_show_weekly" "on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" weekly 2>/dev/null || true)
assert_not_empty "$output" "weekly shown when show_weekly=on"

# Monthly toggle
set_tmux_option "@claudux_show_monthly" "off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" monthly 2>/dev/null || true)
assert_empty "$output" "monthly hidden when show_monthly=off"

set_tmux_option "@claudux_show_monthly" "on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" monthly 2>/dev/null || true)
assert_not_empty "$output" "monthly shown when show_monthly=on"

# Model toggle (controls both sonnet and opus)
set_tmux_option "@claudux_show_model" "off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" sonnet 2>/dev/null || true)
assert_empty "$output" "sonnet hidden when show_model=off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" opus 2>/dev/null || true)
assert_empty "$output" "opus hidden when show_model=off"

set_tmux_option "@claudux_show_model" "on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" sonnet 2>/dev/null || true)
assert_not_empty "$output" "sonnet shown when show_model=on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" opus 2>/dev/null || true)
assert_not_empty "$output" "opus shown when show_model=on"

# Reset toggle
set_tmux_option "@claudux_show_reset" "off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" reset 2>/dev/null || true)
assert_empty "$output" "reset hidden when show_reset=off"

set_tmux_option "@claudux_show_reset" "on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" reset 2>/dev/null || true)
assert_not_empty "$output" "reset shown when show_reset=on"

# Email toggle
set_tmux_option "@claudux_show_email" "off"
output=$("$SCRIPT_DIR/scripts/claudux.sh" email 2>/dev/null || true)
assert_empty "$output" "email hidden when show_email=off"

set_tmux_option "@claudux_show_email" "on"
output=$("$SCRIPT_DIR/scripts/claudux.sh" email 2>/dev/null || true)
assert_not_empty "$output" "email shown when show_email=on"

echo ""
echo "=== CONF-02: Threshold Tests ==="

# High thresholds: 50% usage should be green (colour34)
set_tmux_option "@claudux_warning_threshold" "90"
set_tmux_option "@claudux_critical_threshold" "95"
output=$(render_bar 50 10)
assert_contains "$output" "colour34" "50% is green with warning=90, critical=95"

# Low thresholds: 50% usage should be red (colour196)
set_tmux_option "@claudux_warning_threshold" "30"
set_tmux_option "@claudux_critical_threshold" "40"
output=$(render_bar 50 10)
assert_contains "$output" "colour196" "50% is red with warning=30, critical=40"

# Mid thresholds: 50% usage should be yellow (colour220)
set_tmux_option "@claudux_warning_threshold" "40"
set_tmux_option "@claudux_critical_threshold" "60"
output=$(render_bar 50 10)
assert_contains "$output" "colour220" "50% is yellow with warning=40, critical=60"

# Reset thresholds to defaults for remaining tests
set_tmux_option "@claudux_warning_threshold" "$CLAUDUX_DEFAULT_WARNING_THRESHOLD"
set_tmux_option "@claudux_critical_threshold" "$CLAUDUX_DEFAULT_CRITICAL_THRESHOLD"

echo ""
echo "=== CONF-03: Refresh Interval Tests ==="

# Write fresh cache, then check staleness with short interval
setup_test_cache
set_tmux_option "@claudux_refresh_interval" "9999"
if ! is_cache_stale; then
    pass "cache fresh with refresh_interval=9999"
else
    fail "cache should be fresh with refresh_interval=9999"
fi

# Very short interval — cache should be stale after minimal wait
set_tmux_option "@claudux_refresh_interval" "0"
if is_cache_stale; then
    pass "cache stale with refresh_interval=0"
else
    fail "cache should be stale with refresh_interval=0"
fi

# Reset
set_tmux_option "@claudux_refresh_interval" "$CLAUDUX_DEFAULT_REFRESH_INTERVAL"

echo ""
echo "=== CONF-05: Bar Length Tests ==="

# Standard bar length (10)
output=$(render_bar 50 10)
# Count filled + empty characters (Unicode block chars)
bar_chars=$(printf '%s' "$output" | sed 's/#\[[^]]*\]//g' | tr -d '[]' | wc -m | tr -d ' ')
if [[ "$bar_chars" -eq 10 ]]; then
    pass "bar_length=10 produces 10 characters"
else
    fail "bar_length=10 should produce 10 chars (got $bar_chars)"
fi

# Longer bar (20)
output=$(render_bar 50 20)
bar_chars=$(printf '%s' "$output" | sed 's/#\[[^]]*\]//g' | tr -d '[]' | wc -m | tr -d ' ')
if [[ "$bar_chars" -eq 20 ]]; then
    pass "bar_length=20 produces 20 characters"
else
    fail "bar_length=20 should produce 20 chars (got $bar_chars)"
fi

# Clamped bar (3 -> 5 minimum)
output=$(render_bar 50 3)
bar_chars=$(printf '%s' "$output" | sed 's/#\[[^]]*\]//g' | tr -d '[]' | wc -m | tr -d ' ')
if [[ "$bar_chars" -eq 5 ]]; then
    pass "bar_length=3 clamped to 5 characters"
else
    fail "bar_length=3 should clamp to 5 chars (got $bar_chars)"
fi

# Max clamped bar (50 -> 30)
output=$(render_bar 50 50)
bar_chars=$(printf '%s' "$output" | sed 's/#\[[^]]*\]//g' | tr -d '[]' | wc -m | tr -d ' ')
if [[ "$bar_chars" -eq 30 ]]; then
    pass "bar_length=50 clamped to 30 characters"
else
    fail "bar_length=50 should clamp to 30 chars (got $bar_chars)"
fi

# ─── Results ─────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
