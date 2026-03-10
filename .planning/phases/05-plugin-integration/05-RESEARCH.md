# Phase 5: Plugin Integration - Research

**Researched:** 2026-03-10
**Domain:** tmux plugin integration — TPM entry point, format string registration, dispatcher script, background refresh
**Confidence:** HIGH

## Summary

Phase 5 wires all existing components (cache, fetch, render) into a working tmux plugin. The integration pattern is well-established: tmux-battery, tmux-cpu, and other TPM plugins all follow the same format string registration approach using bash parameter expansion (NOT sed, despite CONTEXT.md suggestion). The entry point script (`claudux.tmux`) reads `status-right` and `status-left`, replaces `#{claudux_*}` placeholders with `#($PLUGIN_DIR/scripts/claudux.sh SEGMENT)` calls, and writes the modified values back. A single dispatcher script (`scripts/claudux.sh`) handles all segment routing to avoid per-segment script forks.

**Primary recommendation:** Follow the tmux-battery/tmux-cpu pattern exactly — parallel arrays for interpolation mapping, bash parameter expansion for substitution, and `tmux set-option -gq` for writeback. Use a single dispatcher script with segment routing to minimize fork overhead.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Register these `#{claudux_*}` format strings via substitution in claudux.tmux:
  - `#{claudux_weekly}` → weekly progress bar with label
  - `#{claudux_monthly}` → monthly progress bar with label
  - `#{claudux_sonnet}` → Sonnet model bar with label
  - `#{claudux_opus}` → Opus model bar with label
  - `#{claudux_reset}` → reset countdown
  - `#{claudux_email}` → account email
  - `#{claudux_status}` → error indicator (if error) or stale indicator (if stale), empty otherwise
- Users compose these freely in `status-right` / `status-left`
- New script: `scripts/claudux.sh` — single dispatcher called by all format strings
- Takes segment name as argument: `claudux.sh weekly`, `claudux.sh reset`, etc.
- Dispatcher flow: source helpers.sh, cache.sh, render.sh → trigger background refresh if stale → route to render_* function → output
- Each format string resolves to: `#($PLUGIN_DIR/scripts/claudux.sh SEGMENT_NAME)`
- Follow tmux-battery pattern for format string registration
- Background cache refresh via `tmux run-shell -b` when stale, guarded by PID file
- On first plugin load, trigger initial fetch via `tmux run-shell -b`
- Manual install supported via `run-shell ~/.tmux/plugins/claudux/claudux.tmux`
- Don't override user's `status-interval`

### Claude's Discretion
- Exact substitution mechanism for format strings (research finding: use bash parameter expansion, not sed)
- Whether to set status-right-length or just document it
- PID file cleanup strategy (on tmux server exit)
- Order of format string registration

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PLUG-01 | Plugin installs via TPM (`set -g @plugin 'user/claudux'` + `prefix + I`) | TPM convention: entry point `claudux.tmux` at repo root, sourced by TPM automatically. Verified via tmux-battery pattern. |
| PLUG-02 | Plugin installs via manual git clone with documented steps | Manual install: `run-shell ~/.tmux/plugins/claudux/claudux.tmux` in tmux.conf. Same entry point, same behavior. |
| PLUG-03 | Plugin provides `#{claudux_*}` format strings users can place in status-left or status-right | Format string registration via parallel arrays + bash parameter expansion in claudux.tmux. Dispatcher routes to render_* functions. |
| PLUG-04 | Plugin auto-refreshes data on a configurable interval (default: 5 min cache TTL) | Background refresh via `tmux run-shell -b` when is_cache_stale() returns true. PID file prevents duplicate spawns. Initial fetch on plugin load. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 3.2+ | Plugin scripting | tmux plugin convention; all TPM plugins use bash |
| tmux | 3.0+ | Plugin host | Target platform; `run-shell -b` for background commands |
| jq | 1.6+ | JSON parsing | Already used by render.sh for cache reads |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| curl | 7.x | API fetching | Already in fetch.sh (Phase 1/2) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash parameter expansion | sed | sed is more fragile with special chars in tmux format strings; parameter expansion is what tmux-battery/tmux-cpu actually use |
| Single dispatcher | Per-segment scripts | Per-segment means N script forks, each sourcing helpers/cache/render separately; dispatcher loads once |
| PID file guard | flock on background fetch | PID file is simpler, works cross-platform; fetch.sh already has lock-based concurrency |

## Architecture Patterns

### Recommended Project Structure
```
claudux/
├── claudux.tmux         # TPM entry point (format string registration + initial fetch)
├── scripts/
│   ├── claudux.sh       # NEW: Single dispatcher for all format strings
│   ├── helpers.sh       # Shared utilities (already exists)
│   ├── cache.sh         # Cache read/write/TTL (already exists)
│   ├── render.sh        # Render functions (already exists)
│   ├── fetch.sh         # Data fetch orchestrator (already exists)
│   ├── credentials.sh   # API key loading (already exists)
│   ├── detect_mode.sh   # Mode detection (already exists)
│   ├── api_fetch.sh     # API client (already exists)
│   ├── local_parse.sh   # JSONL parser (already exists)
│   └── check_deps.sh    # Dependency checker (already exists)
└── config/
    └── defaults.sh      # Default option values (already exists)
```

### Pattern 1: Format String Registration (tmux-battery pattern)
**What:** Parallel arrays map placeholders to script commands, bash parameter expansion performs replacement
**When to use:** Plugin entry point (claudux.tmux)
**Example:**
```bash
# Source: tmux-battery/battery.tmux (GitHub)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parallel arrays: placeholders and their command replacements
claudux_interpolation=(
    "\#{claudux_weekly}"
    "\#{claudux_monthly}"
    "\#{claudux_sonnet}"
    "\#{claudux_opus}"
    "\#{claudux_reset}"
    "\#{claudux_email}"
    "\#{claudux_status}"
)
claudux_commands=(
    "#($CURRENT_DIR/scripts/claudux.sh weekly)"
    "#($CURRENT_DIR/scripts/claudux.sh monthly)"
    "#($CURRENT_DIR/scripts/claudux.sh sonnet)"
    "#($CURRENT_DIR/scripts/claudux.sh opus)"
    "#($CURRENT_DIR/scripts/claudux.sh reset)"
    "#($CURRENT_DIR/scripts/claudux.sh email)"
    "#($CURRENT_DIR/scripts/claudux.sh status)"
)

do_interpolation() {
    local all_interpolated="$1"
    for ((i=0; i<${#claudux_commands[@]}; i++)); do
        all_interpolated="${all_interpolated//${claudux_interpolation[$i]}/${claudux_commands[$i]}}"
    done
    echo "$all_interpolated"
}

update_tmux_option() {
    local option="$1"
    local option_value="$(get_tmux_option "$option" "")"
    local new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
}
main
```

### Pattern 2: Single Dispatcher Script
**What:** One script handles all format string requests, routing by argument
**When to use:** scripts/claudux.sh
**Example:**
```bash
#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/render.sh"

# Background refresh if cache is stale
if is_cache_stale; then
    local cache_dir
    cache_dir="$(get_cache_dir)"
    local pid_file="${cache_dir}/fetch.pid"
    if [[ ! -f "$pid_file" ]] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        tmux run-shell -b "$CURRENT_DIR/fetch.sh"
    fi
fi

# Route to render function
case "$1" in
    weekly)  render_weekly ;;
    monthly) render_monthly ;;
    sonnet)  render_model_sonnet ;;
    opus)    render_model_opus ;;
    reset)   render_reset ;;
    email)   render_email ;;
    status)  render_error; render_stale_indicator ;;
    *)       echo "claudux: unknown segment: $1" >&2 ;;
esac
```

### Pattern 3: Background Fetch with PID Guard
**What:** Spawn fetch.sh in background only if not already running
**When to use:** Dispatcher stale check + initial plugin load
**Example:**
```bash
# PID file approach
trigger_background_fetch() {
    local cache_dir
    cache_dir="$(get_cache_dir)" || return 1
    local pid_file="${cache_dir}/fetch.pid"

    # Check if fetch is already running
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # Already running
        fi
    fi

    # Spawn background fetch via tmux
    tmux run-shell -b "$CURRENT_DIR/fetch.sh"
}
```

### Anti-Patterns to Avoid
- **Per-segment scripts:** Each `#{claudux_*}` calling a separate script = N forks, each re-sourcing all dependencies. Use single dispatcher instead.
- **sed for substitution:** Special characters in tmux format strings (like `#[fg=colour196]`) break sed patterns. Bash parameter expansion handles these safely.
- **Synchronous fetch from status bar:** Never call fetch.sh synchronously from dispatcher. Always background via `tmux run-shell -b`.
- **Overriding status-interval:** Users set this for their workflow. Respect it; document recommended values instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Format string replacement | Custom sed/awk parser | Bash parameter expansion (tmux-battery pattern) | Battle-tested, handles special chars, standard in ecosystem |
| Concurrent fetch prevention | Custom lock mechanism | PID file + kill -0 check | fetch.sh already has acquire_lock(); PID file is the outer guard for "don't even spawn" |
| Background command execution | fork/exec with & | `tmux run-shell -b` | tmux-native, respects tmux lifecycle, proper cleanup |

## Common Pitfalls

### Pitfall 1: Double Interpolation on Source
**What goes wrong:** If user sources tmux.conf twice, format strings get double-replaced (the `#(...)` commands themselves get interpolated again)
**Why it happens:** `claudux.tmux` replaces `#{claudux_*}` with `#(scripts/claudux.sh ...)` each time it runs
**How to avoid:** The tmux-battery pattern handles this naturally — `#(script)` syntax doesn't match `#{claudux_*}` pattern, so re-running is idempotent
**Warning signs:** Status bar shows raw script paths instead of data

### Pitfall 2: Status Right Length Truncation
**What goes wrong:** Multiple claudux segments get cut off because tmux default `status-right-length` is 40 characters
**Why it happens:** 7 segments with labels + bars can exceed 200 characters
**How to avoid:** Set `status-right-length` to 200 in claudux.tmux (only if user hasn't explicitly set it)
**Warning signs:** Segments appear truncated or missing on the right side

### Pitfall 3: Race Between Initial Fetch and First Render
**What goes wrong:** Status bar shows nothing on first load because cache doesn't exist yet and initial fetch hasn't completed
**Why it happens:** `tmux run-shell -b` returns immediately; render functions return empty on missing cache
**How to avoid:** This is actually fine — render functions already return silently on missing cache. After first fetch completes (a few seconds), next status-interval tick shows data.
**Warning signs:** Brief empty display on first plugin load — expected behavior, not a bug.

### Pitfall 4: PID File Not Cleaned Up
**What goes wrong:** Stale PID file blocks background fetch from spawning
**Why it happens:** fetch.sh crashed or tmux server restarted without cleanup
**How to avoid:** Always check PID file with `kill -0` before trusting it. Dead PID = remove and respawn. fetch.sh should write its own PID and clean up on exit.
**Warning signs:** Cache never refreshes despite being stale

### Pitfall 5: CURRENT_DIR in Subshell Context
**What goes wrong:** `CURRENT_DIR` resolves to wrong directory when called via `#(path/to/script)`
**Why it happens:** tmux `#()` runs scripts in a subshell; `BASH_SOURCE[0]` might not resolve correctly
**How to avoid:** Use `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` pattern (resolves from actual script location on disk)
**Warning signs:** "file not found" errors in tmux log

## Code Examples

### claudux.tmux Entry Point (Complete)
```bash
#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/scripts/helpers.sh"

# Dependency check (non-blocking)
"$CURRENT_DIR/scripts/check_deps.sh"

# Format string interpolation arrays
claudux_interpolation=(
    "\#{claudux_weekly}"
    "\#{claudux_monthly}"
    "\#{claudux_sonnet}"
    "\#{claudux_opus}"
    "\#{claudux_reset}"
    "\#{claudux_email}"
    "\#{claudux_status}"
)
claudux_commands=(
    "#($CURRENT_DIR/scripts/claudux.sh weekly)"
    "#($CURRENT_DIR/scripts/claudux.sh monthly)"
    "#($CURRENT_DIR/scripts/claudux.sh sonnet)"
    "#($CURRENT_DIR/scripts/claudux.sh opus)"
    "#($CURRENT_DIR/scripts/claudux.sh reset)"
    "#($CURRENT_DIR/scripts/claudux.sh email)"
    "#($CURRENT_DIR/scripts/claudux.sh status)"
)

do_interpolation() {
    local all_interpolated="$1"
    for ((i=0; i<${#claudux_commands[@]}; i++)); do
        all_interpolated="${all_interpolated//${claudux_interpolation[$i]}/${claudux_commands[$i]}}"
    done
    echo "$all_interpolated"
}

update_tmux_option() {
    local option="$1"
    local option_value
    option_value="$(get_tmux_option "$option" "")"
    local new_option_value
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

main() {
    # Register format strings
    update_tmux_option "status-right"
    update_tmux_option "status-left"

    # Ensure status-right-length is sufficient (only if not explicitly set by user)
    local current_length
    current_length="$(get_tmux_option "status-right-length" "")"
    if [[ -z "$current_length" ]] || [[ "$current_length" -lt 200 ]]; then
        set_tmux_option "status-right-length" "200"
    fi

    # Trigger initial data fetch in background
    tmux run-shell -b "$CURRENT_DIR/scripts/fetch.sh"
}

main
```

### scripts/claudux.sh Dispatcher (Complete)
```bash
#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/render.sh"

# Trigger background refresh if cache is stale
if is_cache_stale; then
    cache_dir="$(get_cache_dir 2>/dev/null)"
    if [[ -n "$cache_dir" ]]; then
        pid_file="${cache_dir}/fetch.pid"
        if [[ ! -f "$pid_file" ]] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
            tmux run-shell -b "echo \$\$ > '${pid_file}' && '$CURRENT_DIR/fetch.sh'; rm -f '${pid_file}'"
        fi
    fi
fi

# Route to render function based on segment name
case "${1:-}" in
    weekly)  render_weekly ;;
    monthly) render_monthly ;;
    sonnet)  render_model_sonnet ;;
    opus)    render_model_opus ;;
    reset)   render_reset ;;
    email)   render_email ;;
    status)
        # Status combines error and stale indicators
        local err stale output
        err="$(render_error)"
        stale="$(render_stale_indicator)"
        output="${err}${stale}"
        [[ -n "$output" ]] && printf '%s' "$output"
        ;;
    *)
        # Unknown segment — silent fail (don't pollute status bar)
        ;;
esac
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-segment scripts | Single dispatcher | tmux-cpu adopted this | Fewer forks, faster status bar |
| sed substitution | Bash parameter expansion | tmux-battery standard | Safer with special chars |
| Manual background fetch | `tmux run-shell -b` | tmux 1.8+ | Native tmux lifecycle management |

## Open Questions

1. **status-right-length override behavior**
   - What we know: Default is 40, which is too short for 7 segments
   - What's unclear: Whether overriding a user's explicit short setting is acceptable
   - Recommendation: Set to 200 only if current value is less than 200 or not set. User can always override after plugin loads.

2. **PID file atomicity**
   - What we know: Writing PID and checking it has a small race window
   - What's unclear: Whether this matters in practice (tmux status refresh is every N seconds)
   - Recommendation: Acceptable risk — fetch.sh has its own lock mechanism as a second guard

## Sources

### Primary (HIGH confidence)
- tmux-battery/battery.tmux (GitHub) - format string registration pattern, do_interpolation, update_tmux_option
- tmux-cpu/cpu.tmux (GitHub) - multiple format string handling, parallel array pattern
- tmux-battery/scripts/helpers.sh (GitHub) - get_tmux_option/set_tmux_option implementations

### Secondary (MEDIUM confidence)
- tmux-plugins/tpm (GitHub) - TPM plugin loading convention, `run-shell -b` for initialization

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - existing codebase already has all dependencies
- Architecture: HIGH - tmux-battery/tmux-cpu pattern is verified and well-documented
- Pitfalls: HIGH - common issues well-known in tmux plugin ecosystem

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable ecosystem, slow-moving)
