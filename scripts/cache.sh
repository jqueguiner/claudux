#!/usr/bin/env bash
# cache.sh — Cache read/write/TTL/locking for claudux tmux plugin
# Provides atomic writes, cross-platform locking, and staleness detection.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

# cache_read — Read and output cache file contents
# Returns 1 if cache file doesn't exist. No network calls.
cache_read() {
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 1
    local cache_file="${cache_dir}/cache.json"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    cat "$cache_file"
    return 0
}

# cache_write — Atomically write content to cache file
# Uses tmpfile + mv pattern to prevent partial reads
# Usage: cache_write '{"key": "value"}'
cache_write() {
    local content="$1"
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 1
    local target="${cache_dir}/cache.json"

    local tmpfile
    tmpfile=$(mktemp "${cache_dir}/cache.XXXXXX") || return 1

    # Clean up tmpfile on error
    trap 'rm -f "$tmpfile"' ERR

    # Write content to tmpfile
    printf '%s\n' "$content" > "$tmpfile" || {
        rm -f "$tmpfile"
        return 1
    }

    # Atomic rename
    mv -f "$tmpfile" "$target" || {
        rm -f "$tmpfile"
        return 1
    }

    # Clear error trap
    trap - ERR
    return 0
}

# is_cache_stale — Check if cache is older than TTL
# Returns 0 (true) if stale or missing, 1 (false) if fresh
# Usage: is_cache_stale [ttl_seconds]
is_cache_stale() {
    local ttl="${1:-}"
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 0
    local cache_file="${cache_dir}/cache.json"

    # No cache file = stale
    if [[ ! -f "$cache_file" ]]; then
        return 0
    fi

    # Use provided TTL or read from tmux option with default
    if [[ -z "$ttl" ]]; then
        ttl="$(get_tmux_option "@claudux_refresh_interval" "$CLAUDUX_DEFAULT_REFRESH_INTERVAL")"
    fi

    local mtime
    mtime=$(get_file_mtime "$cache_file") || return 0

    local now
    now=$(date +%s)
    local age=$(( now - mtime ))

    [[ $age -ge $ttl ]]
}

# acquire_lock — Cross-platform file locking
# Linux: uses flock. macOS/BSD: uses mkdir-based lock with PID tracking.
# Returns 0 on success, 1 on timeout
# Usage: acquire_lock
acquire_lock() {
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 1
    local lockpath="${cache_dir}/cache.lock"
    local timeout=10

    if command -v flock >/dev/null 2>&1; then
        # Linux: use flock on file descriptor 9
        exec 9>"$lockpath"
        flock -w "$timeout" 9
        return $?
    else
        # macOS/BSD: mkdir-based lock
        local lockdir="${lockpath}.d"
        local deadline=$(( $(date +%s) + timeout ))

        while ! mkdir "$lockdir" 2>/dev/null; do
            # Check for stale lock (dead PID)
            if [[ -f "${lockdir}/pid" ]]; then
                local stored_pid
                stored_pid=$(cat "${lockdir}/pid" 2>/dev/null)
                if [[ -n "$stored_pid" ]] && ! kill -0 "$stored_pid" 2>/dev/null; then
                    # PID is dead — force-remove stale lock
                    rm -rf "$lockdir"
                    continue
                fi
            fi

            if [[ $(date +%s) -ge $deadline ]]; then
                return 1
            fi
            sleep 0.1
        done

        # Write our PID for stale detection
        echo $$ > "${lockdir}/pid"
        return 0
    fi
}

# release_lock — Release the file lock
# Usage: release_lock
release_lock() {
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 1
    local lockpath="${cache_dir}/cache.lock"

    if command -v flock >/dev/null 2>&1; then
        # Linux: close file descriptor
        exec 9>&- 2>/dev/null || true
    else
        # macOS/BSD: remove lock directory
        rm -rf "${lockpath}.d"
    fi
}
