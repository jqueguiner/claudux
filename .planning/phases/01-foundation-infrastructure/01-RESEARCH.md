# Phase 1: Foundation Infrastructure - Research

**Researched:** 2026-03-10
**Domain:** Bash tmux plugin infrastructure (cache, cross-platform, security)
**Confidence:** HIGH

## Summary

Phase 1 builds the secure, cached, cross-platform substrate for the claudux tmux plugin. The domain is pure Bash scripting following established tmux plugin conventions (tmux-battery, tmux-cpu). The technical challenges are well-understood: atomic file writes via tmpfile+mv, cross-platform stat differences between GNU/Linux and BSD/macOS, portable file locking without flock on macOS, and credential security via environment variables and permission-restricted config files.

The primary risk area is cross-platform compatibility -- GNU vs BSD command differences for `stat`, `date`, and file locking. These are solved problems with well-documented patterns. The secondary risk is Bash version requirements: macOS ships Bash 3.2 but the project targets Bash 4.0+ (Homebrew provides 5.x). This should be documented as a dependency.

**Primary recommendation:** Follow tmux-battery/tmux-cpu conventions exactly for plugin structure. Use `uname -s` platform detection to dispatch to GNU vs BSD variants of `stat`. Use `mkdir`-based locking (not `flock`) for full cross-platform support.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Directory structure follows tmux-battery/tmux-cpu convention: `claudux.tmux` entry point, `scripts/` for executables, `config/` for defaults
- Cache location: `${XDG_CACHE_HOME:-$HOME/.cache}/claudux/cache.json`
- Cache TTL: configurable via `@claudux_refresh_interval`, default 300 seconds
- Atomic writes: tmpfile + mv pattern
- Lock file: `flock` on Linux, mkdir-based fallback on macOS
- API key: `$ANTHROPIC_ADMIN_API_KEY` env var primary, `~/.config/claudux/credentials` file secondary
- Never pass key as CLI argument
- Ship `.gitignore` covering credential patterns
- Platform detection via `uname -s` in helpers.sh
- All scripts use `#!/usr/bin/env bash` shebang
- Target Bash 4.0+
- Dependency checker: jq, curl, bash version -- warn via tmux display-message, don't crash
- All defaults in `config/defaults.sh`
- Flat `scripts/` directory structure

### Claude's Discretion
- Exact error message wording
- Whether to use color in dependency check warnings
- Internal logging approach (stderr, log file, or tmux display-message)
- Specific flock vs mkdir lock implementation details

### Deferred Ideas (OUT OF SCOPE)
- None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PLUG-05 | Plugin works on Linux (GNU) and macOS (BSD) with tmux 3.0+ | Cross-platform stat/date patterns, uname detection, portable locking |
| DATA-04 | Plugin caches API responses to a file with TTL to avoid rate limits | Atomic write pattern (mktemp + mv), mtime-based TTL check |
| DATA-05 | Plugin never makes synchronous API calls from tmux status bar | Cache-only read architecture, status bar scripts read cache.json only |
| SECR-01 | API key from env var or config file with 600 permissions | Environment variable reading, chmod 600 pattern, XDG paths |
| SECR-02 | API key never passed as CLI argument | Sourced/read from file or env, never in command args |
| SECR-03 | Plugin ships with .gitignore covering credential config files | Standard .gitignore patterns for config directories |
| CONF-04 | API key configurable via env var or config file (never CLI argument) | Same as SECR-01/SECR-02, credential loading function |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 4.0+ | Script runtime | Required for associative arrays, `[[` improvements; macOS users need Homebrew bash |
| tmux | 3.0+ | Host environment | `show-option -gqv` for quiet option reading; format string interpolation |
| jq | 1.6+ | JSON parsing | Cache file is JSON; jq is the standard CLI JSON processor |
| curl | 7.x | HTTP client | API calls in background refresh (Phase 2, but dependency checked here) |
| mktemp | GNU/BSD | Temporary file creation | Atomic write pattern; available on both Linux and macOS |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| uname | Platform detection | Every cross-platform branch point |
| stat | File modification time | Cache staleness check |
| date | Epoch timestamp | TTL arithmetic |
| flock | File locking (Linux) | Cache write serialization on Linux |
| mkdir -p | Lock directory (macOS) | Cache write serialization on macOS/BSD |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq | Python/Node JSON | jq is lighter, no runtime dependency; but is an external dep |
| flock everywhere | mkdir everywhere | flock is more robust on Linux (auto-cleanup on fd close); mkdir needs manual trap cleanup |
| `$XDG_CONFIG_HOME` for credentials | `$XDG_DATA_HOME` | XDG spec recommends data_home for secrets since config_home gets synced; but `~/.config` is the convention users expect |

## Architecture Patterns

### Recommended Project Structure
```
claudux/
├── claudux.tmux           # TPM entry point (stub in Phase 1)
├── scripts/
│   ├── helpers.sh         # Shared utilities (get_tmux_option, platform detection)
│   ├── cache.sh           # Cache read/write/TTL/locking
│   └── check_deps.sh      # Dependency checker (jq, curl, bash version)
├── config/
│   └── defaults.sh        # Default tmux option values
└── .gitignore             # Credential and cache exclusions
```

### Pattern 1: TPM Plugin Entry Point
**What:** The `.tmux` file is the plugin entry point sourced by TPM. It registers format string interpolations and sources helpers.
**When to use:** Every tmux plugin needs exactly one `*.tmux` file.
**Example:**
```bash
#!/usr/bin/env bash
# Source: tmux-battery/battery.tmux, tmux-cpu/cpu.tmux

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

# Format string interpolation arrays
claudux_interpolation=(
    "\#{claudux_weekly}"
    "\#{claudux_monthly}"
)
claudux_commands=(
    "#($CURRENT_DIR/scripts/weekly.sh)"
    "#($CURRENT_DIR/scripts/monthly.sh)"
)

do_interpolation() {
    local string="$1"
    for ((i=0; i<${#claudux_interpolation[@]}; i++)); do
        string="${string/${claudux_interpolation[$i]}/${claudux_commands[$i]}}"
    done
    echo "$string"
}

update_tmux_option() {
    local option="$1"
    local option_value="$(get_tmux_option "$option")"
    local new_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_value"
}

main() {
    # Check dependencies first
    "$CURRENT_DIR/scripts/check_deps.sh"

    update_tmux_option "status-right"
    update_tmux_option "status-left"
}

main
```

### Pattern 2: get_tmux_option Helper
**What:** Standard helper to read tmux options with defaults. Used by every tmux plugin.
**When to use:** Any time you need a configurable value.
**Example:**
```bash
# Source: tmux-battery/scripts/helpers.sh
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -gqv "$option")"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

set_tmux_option() {
    tmux set-option -gq "$1" "$2"
}
```

### Pattern 3: Platform-Aware stat for mtime
**What:** Dispatch to GNU or BSD stat based on uname detection.
**When to use:** Checking cache file age.
**Example:**
```bash
get_file_mtime() {
    local file="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f %m "$file"
    else
        stat -c %Y "$file"
    fi
}

is_cache_stale() {
    local cache_file="$1"
    local ttl="$2"

    if [[ ! -f "$cache_file" ]]; then
        return 0  # No cache = stale
    fi

    local mtime
    mtime=$(get_file_mtime "$cache_file")
    local now
    now=$(date +%s)
    local age=$(( now - mtime ))

    [[ $age -ge $ttl ]]
}
```

### Pattern 4: Atomic Write with tmpfile + mv
**What:** Write to a temp file in the same directory, then atomically rename. Prevents partial reads.
**When to use:** Writing cache.json.
**Example:**
```bash
atomic_write() {
    local target="$1"
    local content="$2"
    local dir
    dir="$(dirname "$target")"

    local tmpfile
    tmpfile=$(mktemp "${dir}/cache.XXXXXX") || return 1

    # Write content
    printf '%s\n' "$content" > "$tmpfile" || { rm -f "$tmpfile"; return 1; }

    # Atomic rename
    mv -f "$tmpfile" "$target" || { rm -f "$tmpfile"; return 1; }
}
```

### Pattern 5: Cross-Platform File Locking
**What:** Use flock on Linux, mkdir-based lock on macOS.
**When to use:** Serializing cache writes from concurrent processes.
**Example:**
```bash
acquire_lock() {
    local lockfile="$1"
    local timeout="${2:-10}"

    if command -v flock >/dev/null 2>&1; then
        # Linux: use flock
        exec 9>"$lockfile"
        flock -w "$timeout" 9
        return $?
    else
        # macOS/BSD: mkdir-based lock
        local lockdir="${lockfile}.d"
        local deadline=$(( $(date +%s) + timeout ))
        while ! mkdir "$lockdir" 2>/dev/null; do
            if [[ $(date +%s) -ge $deadline ]]; then
                return 1
            fi
            sleep 0.1
        done
        trap 'rm -rf -- "$lockdir"' EXIT
        return 0
    fi
}

release_lock() {
    local lockfile="$1"
    if command -v flock >/dev/null 2>&1; then
        exec 9>&-
    else
        rm -rf "${lockfile}.d"
    fi
}
```

### Anti-Patterns to Avoid
- **Non-atomic cache writes:** Writing directly to `cache.json` risks partial reads by status bar scripts. Always use tmpfile+mv.
- **`flock` without fallback:** macOS does not ship flock. Always provide mkdir alternative.
- **Synchronous API calls in status bar:** Status bar scripts run on every tmux refresh (~15s). Network calls here freeze the entire status bar.
- **CLI argument secrets:** `ps aux` exposes all command arguments. Never `curl -H "Authorization: $KEY"` in a subprocess visible via ps -- use `--config -` or `-H @-` patterns.
- **`/bin/bash` shebang:** macOS `/bin/bash` is 3.2 (Apple won't upgrade due to GPLv3). Use `#!/usr/bin/env bash` to pick up Homebrew bash.
- **`mkdir -p` for locks:** `-p` creates parent directories AND never fails if directory exists. Use plain `mkdir` (fails if exists = atomic check).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | sed/awk/grep JSON | jq | JSON has escaping, nesting, edge cases; jq handles all correctly |
| Temp files | manual $RANDOM naming | mktemp | Race conditions, cleanup, security; mktemp is POSIX-standard |
| Option reading | direct tmux show-option | get_tmux_option wrapper | Consistent defaults, quiet mode, reusable across all scripts |
| Epoch timestamps | parsing date strings | `date +%s` | Works on both GNU and BSD; epoch arithmetic is trivial |

**Key insight:** The tmux plugin ecosystem has standardized on these patterns. Deviating makes the plugin harder to maintain and contribute to.

## Common Pitfalls

### Pitfall 1: Bash Version on macOS
**What goes wrong:** Script uses Bash 4+ features (associative arrays, `${var,,}`, `[[ =~ ]]` with regex groups) but macOS ships Bash 3.2.
**Why it happens:** Apple stopped updating Bash due to GPLv3 licensing of Bash 4+.
**How to avoid:** Document Bash 4+ requirement, check version in `check_deps.sh`, guide users to `brew install bash`.
**Warning signs:** Syntax errors on macOS that don't appear on Linux.

### Pitfall 2: stat Format String Incompatibility
**What goes wrong:** `stat -c %Y file` fails on macOS with "illegal option -- c".
**Why it happens:** GNU stat uses `-c` for format, BSD stat uses `-f`. Different format specifiers too (`%Y` vs `%m` for mtime epoch).
**How to avoid:** Always dispatch through a platform-detection wrapper function. Never call `stat` directly with format flags.
**Warning signs:** "illegal option" errors in tmux logs on macOS.

### Pitfall 3: Lock File Stale After Crash
**What goes wrong:** Script crashes or is killed, leaving lock directory/file behind. Subsequent runs can't acquire the lock.
**Why it happens:** `mkdir`-based locks don't auto-release on process death (unlike `flock` which releases on fd close).
**How to avoid:** Store PID in lock directory, check if PID is still alive before declaring stale. Add timeout + stale detection.
**Warning signs:** Cache stops updating, stale data displayed indefinitely.

### Pitfall 4: Race Condition in Cache TTL Check
**What goes wrong:** Two processes both detect stale cache, both trigger API refresh simultaneously.
**Why it happens:** Check-then-act without locking between the staleness check and the refresh trigger.
**How to avoid:** Acquire lock before checking staleness. Or: accept double-fetch as harmless (idempotent write).
**Warning signs:** Double API calls visible in rate limit logs.

### Pitfall 5: Credentials in ps Output
**What goes wrong:** API key appears in `ps aux` output because it was passed as a curl argument.
**Why it happens:** Command-line arguments are visible to all users on the system via `/proc/PID/cmdline`.
**How to avoid:** Pass credentials via environment variable to curl, or use `--config -` with stdin. Never `curl -H "X-Api-Key: sk-ant-..."`.
**Warning signs:** Running `ps aux | grep curl` shows the API key.

## Code Examples

### Credential Loading
```bash
# Source: Security best practices for CLI tools
load_api_key() {
    # Priority 1: Environment variable
    if [[ -n "${ANTHROPIC_ADMIN_API_KEY:-}" ]]; then
        echo "$ANTHROPIC_ADMIN_API_KEY"
        return 0
    fi

    # Priority 2: Config file with strict permissions
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/claudux/credentials"
    if [[ -f "$config_file" ]]; then
        # Verify permissions
        local perms
        if [[ "$(uname -s)" == "Darwin" ]]; then
            perms=$(stat -f %Lp "$config_file")
        else
            perms=$(stat -c %a "$config_file")
        fi

        if [[ "$perms" != "600" ]]; then
            echo "WARNING: $config_file has insecure permissions ($perms). Expected 600." >&2
            return 1
        fi

        # Read key (first non-empty, non-comment line)
        grep -v '^[[:space:]]*#' "$config_file" | grep -v '^[[:space:]]*$' | head -1
        return 0
    fi

    return 1  # No key found
}
```

### Cache Directory Initialization
```bash
# Source: XDG Base Directory Specification
init_cache_dir() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir" || {
            echo "ERROR: Cannot create cache directory: $cache_dir" >&2
            return 1
        }
    fi
    echo "$cache_dir"
}
```

### Dependency Checker
```bash
# Source: tmux plugin conventions
check_deps() {
    local missing=()

    # Check bash version
    local bash_major="${BASH_VERSINFO[0]}"
    if [[ "$bash_major" -lt 4 ]]; then
        tmux display-message "claudux: Bash 4.0+ required (found $BASH_VERSION). Install via: brew install bash" 2>/dev/null
        missing+=("bash 4+")
    fi

    # Check jq
    if ! command -v jq >/dev/null 2>&1; then
        tmux display-message "claudux: jq required. Install via: brew install jq / sudo apt install jq" 2>/dev/null
        missing+=("jq")
    fi

    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        tmux display-message "claudux: curl required. Install via: brew install curl / sudo apt install curl" 2>/dev/null
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        return 1
    fi
    return 0
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `/bin/bash` shebang | `#!/usr/bin/env bash` | Post-macOS Catalina (2019) | Required for Homebrew bash on macOS |
| Simple lockfiles (touch) | mkdir atomic + flock | Long-standing best practice | Prevents race conditions |
| Inline defaults | Centralized defaults.sh | tmux plugin convention | Single source of truth for options |
| Raw curl output | jq-parsed JSON cache | Standard practice | Structured, queryable cache data |

## Open Questions

1. **Curl credential passing**
   - What we know: `curl -H "X-Api-Key: $KEY"` exposes key in `ps aux`
   - What's unclear: Best curl pattern for hiding credentials while staying Bash-simple
   - Recommendation: Use `curl --config -` feeding config via heredoc/stdin, or export to env and use `-H "X-Api-Key: $ANTHROPIC_ADMIN_API_KEY"` (env vars don't appear in ps, but the expanded value in -H does). Safest: write a temp netrc-style file with 600 perms, use `--netrc-file`, delete after.

2. **Lock stale detection timeout**
   - What we know: mkdir locks persist after crashes
   - What's unclear: Optimal timeout before declaring a lock stale
   - Recommendation: Write PID to a file inside the lock directory. On acquire failure, check if stored PID is alive (`kill -0 $pid`). If dead, force-remove and re-acquire. Default stale timeout: 60 seconds.

## Sources

### Primary (HIGH confidence)
- tmux-battery plugin source (GitHub) - plugin structure, get_tmux_option, interpolation pattern
- tmux-cpu plugin source (GitHub) - parallel format string registration pattern
- Greg's Wiki BashFAQ/045 - file locking patterns (mkdir, flock, ln -s)
- Greg's Wiki BashFAQ/062 - atomic file creation with tmpfile
- XDG Base Directory Specification - cache and config directory conventions

### Secondary (MEDIUM confidence)
- tech-champion.com - cross-platform shell differences (GNU vs BSD stat, date)
- Apple Developer docs - shell scripting portability for macOS

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - tmux plugin ecosystem is mature and well-documented
- Architecture: HIGH - following established tmux-battery/tmux-cpu patterns
- Pitfalls: HIGH - cross-platform Bash issues are extensively documented
- Security: HIGH - credential handling patterns are well-established

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable domain, unlikely to change)
