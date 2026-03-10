# Phase 4: Metadata & Status Display - Research

**Researched:** 2026-03-10
**Domain:** Bash/tmux status bar rendering — metadata segments
**Confidence:** HIGH

## Summary

Phase 4 adds four new render functions to `scripts/render.sh`: reset countdown (`render_reset`), account email (`render_email`), stale data indicator (`render_stale_indicator`), and error state (`render_error`). All four follow the established Phase 3 pattern: source helpers.sh + cache.sh, read via `cache_read()`, extract with jq, return tmux-formatted strings, and silently return 0 on missing/error data.

The cache schema already contains `reset_at` fields (currently hardcoded to 0), `account.email`, and `error` fields. The render functions simply need to read and format these existing fields. The stale indicator is the only function that needs to inspect the cache file's filesystem metadata (mtime) rather than just its JSON content.

**Primary recommendation:** Add all four render functions to the existing `scripts/render.sh`, following the exact same pattern as `render_weekly`/`render_monthly`/`render_model_*`. Use cross-platform date arithmetic from `helpers.sh` for the reset countdown.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Reset countdown format: `#[fg=colour245]R:#[default] 2h 15m` with adaptive units (Xd Yh for >24h, Xh Ym for <24h, Xm for <1h); show nearest reset; silent on missing
- Account email: `#[fg=colour245]email#[default]` dimmed, truncate at 20 chars + `...`, read from `cache.json -> account.email`, silent on missing
- Stale indicator: append `#[fg=colour136]?#[default]` when cache mtime > 2x refresh interval; implemented as `render_stale_indicator` function
- Error indicator: `#[fg=colour196][!] error_code#[default]` red, read from cache error field; implemented as `render_error` function

### Claude's Discretion
- Exact time rounding behavior (round minutes up or down)
- Email truncation threshold (20 chars suggested but flexible)
- Whether to log detailed error messages to a file alongside the short indicator

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DISP-05 | User sees quota reset dates with associated time (relative format: "resets in Xh Ym") | `render_reset` reads `reset_at` from cache weekly/monthly sections, uses cross-platform date math to compute relative time |
| DISP-06 | User sees the account email associated with their API key or subscription | `render_email` reads `account.email` from cache, truncates and formats with dim color |
| DISP-08 | User sees a visual indicator when cached data is stale beyond expected refresh interval | `render_stale_indicator` compares cache mtime against 2x refresh interval using `get_file_mtime()` from helpers.sh |
| DISP-09 | User sees a clear error indicator when API auth fails or data is unavailable | `render_error` checks cache `error` field, outputs `[!] error_code` in red |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Shell scripting | tmux plugin standard; macOS ships 3.2 |
| jq | 1.6+ | JSON parsing | Already a project dependency (Phase 1) |
| tmux | 3.0+ | Status bar host | Target platform |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| date (GNU/BSD) | system | Epoch/relative time math | Reset countdown calculation |
| stat (GNU/BSD) | system | File mtime detection | Stale data indicator |
| bc | system | Floating point math | Not needed (integer arithmetic sufficient) |

### Alternatives Considered
None -- this phase uses the same stack as Phases 1-3.

## Architecture Patterns

### Recommended Project Structure
No new files needed. All changes go into:
```
scripts/
└── render.sh          # Add 4 new render_* functions
```

### Pattern 1: Self-Contained Render Function
**What:** Each render function reads cache independently, checks for errors, extracts data, formats output
**When to use:** Every new status bar segment
**Example:**
```bash
render_foo() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0
    # Extract and format
    printf '#[fg=colour245]F:#[default] %s' "$value"
}
```

### Pattern 2: Cross-Platform Date Arithmetic
**What:** Use `get_platform()` to branch between GNU date and BSD date for epoch math
**When to use:** Reset countdown calculation (converting epoch reset_at to relative time)
**Example:**
```bash
# Current epoch
local now=$(date +%s)
# Seconds remaining
local remaining=$(( reset_at - now ))
# Convert to hours and minutes
local hours=$(( remaining / 3600 ))
local minutes=$(( (remaining % 3600) / 60 ))
```

### Pattern 3: Silent Failure on Missing Data
**What:** Return 0 without output when data is missing or invalid
**When to use:** All render functions -- prevents broken status bar segments
**Example:** `[[ "$reset_at" -le 0 ]] 2>/dev/null && return 0`

### Anti-Patterns to Avoid
- **Subshell per-field extraction:** Don't call `cache_read` multiple times in a single render function -- read once, extract multiple fields
- **Network calls in render functions:** Never. All data comes from cache.json
- **Hard-coded color codes without tmux format:** Always use `#[fg=colourNNN]` not ANSI escape codes

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File mtime detection | Custom stat parsing | `get_file_mtime()` from helpers.sh | Already handles Linux/macOS differences |
| Platform detection | `uname` checks inline | `get_platform()` from helpers.sh | Cached result, tested |
| Tmux option reading | Direct `tmux show-option` | `get_tmux_option()` from helpers.sh | Handles missing tmux gracefully |
| Cache reading | Direct `cat` of cache file | `cache_read()` from cache.sh | Handles missing file, consistent |

## Common Pitfalls

### Pitfall 1: reset_at = 0 Treated as Valid
**What goes wrong:** Rendering "resets in -Xh" when reset_at is 0 (unknown)
**Why it happens:** Both api_fetch.sh and local_parse.sh set `reset_at: 0` when unknown
**How to avoid:** Guard: `[[ "$reset_at" -le 0 ]] && return 0`
**Warning signs:** Negative countdown values in status bar

### Pitfall 2: BSD date vs GNU date for Epoch Subtraction
**What goes wrong:** `date -d` doesn't exist on macOS; `date -v` doesn't exist on Linux
**Why it happens:** Different date implementations
**How to avoid:** Only use epoch arithmetic (subtraction), no date command needed for relative time
**Warning signs:** "illegal option" errors on macOS

### Pitfall 3: Email with Special Characters in JSON
**What goes wrong:** Printf breaks on emails containing `%` or backslashes
**Why it happens:** `printf '%s'` is safe but `printf "..."` with interpolation is not
**How to avoid:** Always use `printf '%s'` with separate arguments
**Warning signs:** Garbled email display

### Pitfall 4: Stale Indicator Using Cache Content Instead of Mtime
**What goes wrong:** Using `fetched_at` from cache JSON instead of filesystem mtime
**Why it happens:** Seems equivalent but isn't -- if cache write fails partially, mtime is more reliable
**How to avoid:** Use `get_file_mtime()` on the actual cache file
**Warning signs:** Stale indicator not triggering when expected

### Pitfall 5: Truncating Multi-Byte Email Characters
**What goes wrong:** Cutting a UTF-8 character in half when truncating email
**Why it happens:** Bash string slicing counts bytes, not characters
**How to avoid:** For email addresses, ASCII is nearly universal -- this is low risk. If needed, use `${var:0:20}` which works correctly for ASCII.
**Warning signs:** Garbled last character in truncated emails (extremely rare for email addresses)

## Code Examples

### Reset Countdown Rendering
```bash
render_reset() {
    local cache_data
    cache_data=$(cache_read) || return 0
    printf '%s' "$cache_data" | jq -e '.error == null' >/dev/null 2>&1 || return 0

    # Get reset_at from weekly and monthly, pick nearest
    local weekly_reset monthly_reset
    weekly_reset=$(printf '%s' "$cache_data" | jq -r '.weekly.reset_at // 0')
    monthly_reset=$(printf '%s' "$cache_data" | jq -r '.monthly.reset_at // 0')

    # Find nearest non-zero reset
    local reset_at=0
    if [[ "$weekly_reset" -gt 0 ]] && [[ "$monthly_reset" -gt 0 ]]; then
        [[ "$weekly_reset" -le "$monthly_reset" ]] && reset_at="$weekly_reset" || reset_at="$monthly_reset"
    elif [[ "$weekly_reset" -gt 0 ]]; then
        reset_at="$weekly_reset"
    elif [[ "$monthly_reset" -gt 0 ]]; then
        reset_at="$monthly_reset"
    fi
    [[ "$reset_at" -le 0 ]] && return 0

    local now remaining
    now=$(date +%s)
    remaining=$(( reset_at - now ))
    [[ "$remaining" -le 0 ]] && return 0  # Already reset

    # Format based on magnitude
    local days hours minutes
    days=$(( remaining / 86400 ))
    hours=$(( (remaining % 86400) / 3600 ))
    minutes=$(( (remaining % 3600) / 60 ))

    local time_str
    if [[ "$days" -gt 0 ]]; then
        time_str="${days}d ${hours}h"
    elif [[ "$hours" -gt 0 ]]; then
        time_str="${hours}h ${minutes}m"
    else
        time_str="${minutes}m"
    fi

    printf '#[fg=colour245]R:#[default] %s' "$time_str"
}
```

### Error Indicator Rendering
```bash
render_error() {
    local cache_data
    cache_data=$(cache_read) || return 0

    # Check if error field exists and is non-null
    local error_code
    error_code=$(printf '%s' "$cache_data" | jq -r '.error.code // empty')
    [[ -z "$error_code" ]] && return 0

    printf '#[fg=colour196][!] %s#[default]' "$error_code"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ANSI escape codes in tmux | tmux format strings (#[fg=]) | tmux 2.0+ | Must use tmux format, not raw ANSI |

No deprecated patterns relevant to this phase.

## Open Questions

1. **When will `reset_at` be populated with real values?**
   - What we know: Both api_fetch.sh and local_parse.sh currently set `reset_at: 0`
   - What's unclear: The Anthropic Admin API may not expose reset timestamps. Local mode would need to calculate based on billing cycle.
   - Recommendation: Implement `render_reset` to handle non-zero `reset_at` correctly. The function will silently return nothing until a future phase or update populates these values. This keeps the implementation ready without blocking on data availability.

2. **Should `render_email` read from cache or directly from settings?**
   - What we know: api_fetch.sh populates `account.email` from org API. local_parse.sh reads from `~/.claude/settings.json`.
   - What's unclear: Whether cache is always the right source
   - Recommendation: Read from cache only (consistent with all other render functions). The fetch layer is responsible for populating this field.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `scripts/render.sh`, `scripts/cache.sh`, `scripts/helpers.sh`, `scripts/api_fetch.sh`, `scripts/local_parse.sh`
- Cache schema inspection: JSON structure from api_fetch.sh and local_parse.sh output

### Secondary (MEDIUM confidence)
- tmux format string documentation (tmux man page)
- GNU/BSD date command behavior differences

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - same stack as Phases 1-3, no new dependencies
- Architecture: HIGH - follows established render_* pattern exactly
- Pitfalls: HIGH - identified from codebase analysis and cross-platform experience

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable domain, unlikely to change)
