#!/usr/bin/env bash
# fetch.sh — Data fetch orchestrator for claudux tmux plugin
# Main entry point for data refresh. Called by status bar scripts (Phase 5).
# Handles: lock -> staleness check -> detect mode -> fetch data -> cache write -> unlock

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/credentials.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/detect_mode.sh"
source "$CURRENT_DIR/api_fetch.sh"
source "$CURRENT_DIR/local_parse.sh"
source "$CURRENT_DIR/profiles.sh"

# claudux_fetch — Main orchestration function
# Acquires lock, checks staleness, detects mode, fetches data, writes cache.
# Returns: 0 on success, 1 on failure
claudux_fetch() {
    # Step 1: Acquire lock (prevents concurrent fetches from tmux)
    if ! acquire_lock; then
        echo "claudux: could not acquire lock, skipping fetch" >&2
        return 1
    fi

    # Ensure lock is released on exit (any path)
    trap 'release_lock' RETURN

    # Step 2: Check if cache is stale
    if ! is_cache_stale; then
        echo "claudux: cache is fresh, skipping fetch" >&2
        return 0
    fi

    # Step 3: Detect mode
    local mode
    mode=$(detect_mode 2>/dev/null)
    local detect_status=$?

    if [[ $detect_status -ne 0 ]] || [[ "$mode" == "none" ]]; then
        # No data source available -- write error to cache
        local now
        now=$(date +%s)
        local error_json
        error_json=$(printf '{
  "mode": "none",
  "fetched_at": %d,
  "account": {"email": ""},
  "weekly": {"used": 0, "limit": 0, "unit": "tokens", "reset_at": 0},
  "monthly": {"used": 0, "limit": 0, "unit": "tokens", "reset_at": 0},
  "models": {},
  "error": {"code": "no_source", "message": "No API key or Claude Code logs found. Set ANTHROPIC_ADMIN_API_KEY for org mode or use Claude Code for local mode."}
}' "$now")
        cache_write "$error_json"
        return 1
    fi

    # Step 4: Call appropriate fetcher
    local result
    case "$mode" in
        org)
            local api_key
            api_key=$(get_profile_api_key 2>/dev/null) || api_key=$(load_api_key) || {
                echo "claudux: failed to load API key" >&2
                return 1
            }
            result=$(api_fetch "$api_key")
            ;;
        local)
            result=$(parse_local_logs)
            ;;
        *)
            echo "claudux: unknown mode: $mode" >&2
            return 1
            ;;
    esac

    # Step 5: Write result to cache
    if [[ -n "$result" ]]; then
        cache_write "$result"
        echo "claudux: cache updated ($mode mode)" >&2
        return 0
    else
        echo "claudux: fetcher returned empty result" >&2
        return 1
    fi
}

# When executed directly (not sourced), run the fetch
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    claudux_fetch
    exit $?
fi
