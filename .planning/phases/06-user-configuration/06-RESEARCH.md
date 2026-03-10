# Phase 6: User Configuration - Research

**Researched:** 2026-03-10
**Domain:** tmux option wiring / Bash shell scripting
**Confidence:** HIGH

## Summary

Phase 6 is a thin wiring phase. The configuration infrastructure is already fully built: `config/defaults.sh` defines all 9 `CLAUDUX_DEFAULT_*` constants, `helpers.sh` provides `get_tmux_option()` with fallback defaults, and every render function in `render.sh` already reads `@claudux_bar_length`, `@claudux_warning_threshold`, and `@claudux_critical_threshold` via `get_tmux_option`. The cache staleness check in `cache.sh` already reads `@claudux_refresh_interval`.

The only missing functionality is **show/hide toggling** in the dispatcher (`scripts/claudux.sh`). Currently, the dispatcher routes segment names directly to render functions without checking `@claudux_show_*` options. Adding toggle guards before each `render_*` call is the entire scope of new code. Optionally, `render_bar()` should clamp `bar_length` to a valid range (5-30) to prevent garbled output from extreme values.

**Primary recommendation:** Add toggle checks in `claudux.sh` dispatcher before each render call; add bar_length clamping in `render_bar()`; write end-to-end verification tests for all configuration options.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- When `@claudux_show_weekly` is "off": dispatcher outputs nothing for `weekly` segment
- Same for `show_monthly`, `show_model`, `show_reset`, `show_email`
- Implementation: add toggle check in dispatcher before calling render function
- `@claudux_show_model` controls BOTH Sonnet and Opus bars (single toggle, not per-model)
- Default values already defined in `config/defaults.sh` — just wire them into dispatcher
- Toggle option names: `@claudux_show_weekly`, `@claudux_show_monthly`, `@claudux_show_model`, `@claudux_show_reset`, `@claudux_show_email`
- Values: "on" or "off" — standard tmux option convention
- Threshold config (`@claudux_warning_threshold`, `@claudux_critical_threshold`) already read by `render_bar()` — no new wiring needed
- Bar length config (`@claudux_bar_length`) already read by each `render_*` function — no new wiring needed; valid range 5-30 with clamping
- Refresh interval config (`@claudux_refresh_interval`) already read by `is_cache_stale()` — no new wiring needed
- Only the dispatcher (`claudux.sh`) needs modification
- No new scripts needed
- defaults.sh already has all default values defined

### Claude's Discretion
- Whether to add input validation (e.g., clamp bar_length to 5-30)
- Whether to add a `@claudux_mode` override option ("org"/"local"/"auto")
- Log level for debugging configuration issues

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONF-01 | User can toggle which stats are displayed via tmux options (`@claudux_show_*`) | Add toggle guard in dispatcher `case` routing — check `get_tmux_option "@claudux_show_X" "$DEFAULT"` before calling render function |
| CONF-02 | User can customize color thresholds via `@claudux_warning_threshold` and `@claudux_critical_threshold` | Already implemented in `render_bar()` (lines 23-25 of render.sh) — verify end-to-end only |
| CONF-03 | User can set cache refresh interval via `@claudux_refresh_interval` | Already implemented in `is_cache_stale()` (line 71 of cache.sh) — verify end-to-end only |
| CONF-05 | User can set progress bar length via `@claudux_bar_length` | Already read in each `render_*` function — add optional clamping in `render_bar()` for robustness |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 4.0+ | Shell scripting | Already used by entire project; tmux plugins are conventionally Bash |
| tmux | 3.0+ | Option storage and format string rendering | Target platform; `show-option -gqv` is the standard option reading pattern |
| jq | 1.6+ | JSON cache parsing | Already a project dependency for cache reading |

### Supporting
No additional libraries needed. All infrastructure exists.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash toggle check in dispatcher | Per-render-function toggle check | Dispatcher-level is cleaner — single point of control, render functions stay pure |
| String "on"/"off" values | Boolean 0/1 | tmux options are strings by convention; "on"/"off" is what tmux-battery, tmux-cpu use |

## Architecture Patterns

### Recommended Project Structure
```
scripts/
├── claudux.sh       # Dispatcher — ADD toggle guards here
├── helpers.sh       # get_tmux_option() — no changes needed
├── cache.sh         # is_cache_stale() — no changes needed
├── render.sh        # render_bar() — ADD bar_length clamping
config/
└── defaults.sh      # All defaults — no changes needed
```

### Pattern 1: Toggle Guard in Dispatcher
**What:** Check show/hide option before routing to render function
**When to use:** For every segment in the `case` statement
**Example:**
```bash
case "${1:-}" in
    weekly)
        [[ "$(get_tmux_option "@claudux_show_weekly" "$CLAUDUX_DEFAULT_SHOW_WEEKLY")" == "on" ]] && render_weekly
        ;;
    monthly)
        [[ "$(get_tmux_option "@claudux_show_monthly" "$CLAUDUX_DEFAULT_SHOW_MONTHLY")" == "on" ]] && render_monthly
        ;;
    sonnet)
        [[ "$(get_tmux_option "@claudux_show_model" "$CLAUDUX_DEFAULT_SHOW_MODEL")" == "on" ]] && render_model_sonnet
        ;;
    opus)
        [[ "$(get_tmux_option "@claudux_show_model" "$CLAUDUX_DEFAULT_SHOW_MODEL")" == "on" ]] && render_model_opus
        ;;
    reset)
        [[ "$(get_tmux_option "@claudux_show_reset" "$CLAUDUX_DEFAULT_SHOW_RESET")" == "on" ]] && render_reset
        ;;
    email)
        [[ "$(get_tmux_option "@claudux_show_email" "$CLAUDUX_DEFAULT_SHOW_EMAIL")" == "on" ]] && render_email
        ;;
    status)
        # status segment is always shown (error/stale indicators)
        err="$(render_error)"
        stale="$(render_stale_indicator)"
        output="${err}${stale}"
        [[ -n "$output" ]] && printf '%s' "$output"
        ;;
    *)  ;;
esac
```

### Pattern 2: Input Clamping for Bar Length
**What:** Clamp `bar_length` to 5-30 range in `render_bar()`
**When to use:** After reading bar_length from tmux option, before using it
**Example:**
```bash
render_bar() {
    local pct="$1"
    local bar_length="${2:-10}"

    # Clamp bar_length to valid range
    [[ $bar_length -lt 5 ]] 2>/dev/null && bar_length=5
    [[ $bar_length -gt 30 ]] 2>/dev/null && bar_length=30

    # ... rest of function
}
```

### Anti-Patterns to Avoid
- **Toggle check inside render functions:** Don't add show/hide logic to render.sh — render functions should remain pure renderers. The dispatcher owns routing decisions.
- **Creating a new config reading mechanism:** Don't introduce config files for user settings. tmux options are the standard mechanism — they're persistent across sessions, queryable, and follow tmux plugin conventions.
- **Validating option values strictly:** Don't error on unexpected values. If `@claudux_show_weekly` is set to "banana", treat it as "not on" — the `== "on"` check handles this naturally.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Option reading | Custom config parser | `get_tmux_option` | Already built, handles missing options gracefully |
| Default values | Inline defaults | `$CLAUDUX_DEFAULT_*` constants | Single source of truth in defaults.sh |
| Cache TTL | Custom timer | `is_cache_stale()` | Already reads `@claudux_refresh_interval` |

**Key insight:** Phase 6 is wiring, not building. Nearly everything exists — the only code to write is toggle guards and optional clamping.

## Common Pitfalls

### Pitfall 1: Fork Overhead from get_tmux_option
**What goes wrong:** Each `get_tmux_option` call forks a `tmux show-option` subprocess. Multiple calls in the dispatcher add latency to every status bar refresh.
**Why it happens:** tmux status bar calls the dispatcher script every `status-interval` seconds for every segment. Six segments = six script executions per tick.
**How to avoid:** The toggle check adds only ONE `get_tmux_option` call per dispatcher invocation (which handles one segment). This is acceptable — the render functions already make 2-4 calls each. Net overhead is minimal.
**Warning signs:** Status bar visibly lagging or flickering.

### Pitfall 2: Case Sensitivity in Toggle Values
**What goes wrong:** User sets `@claudux_show_weekly "On"` (capital O) and toggle doesn't work.
**Why it happens:** Bash string comparison `== "on"` is case-sensitive.
**How to avoid:** Document that values must be lowercase "on"/"off". This matches tmux plugin conventions (tmux-battery, tmux-cpu all use lowercase). Converting to lowercase adds unnecessary complexity for a non-standard use case.
**Warning signs:** User reports segment not showing despite setting option.

### Pitfall 3: Non-Integer Bar Length
**What goes wrong:** User sets `@claudux_bar_length "abc"` and arithmetic fails.
**Why it happens:** Bash arithmetic on non-integer produces errors.
**How to avoid:** The `2>/dev/null` on clamping comparisons handles this — if comparison fails, the original (invalid) value passes through, and the `render_bar` arithmetic will default to 0 segments, producing an empty bar. Not ideal but not a crash. For better robustness, could add an integer check.
**Warning signs:** Empty or malformed progress bars.

### Pitfall 4: Status Segment Toggle
**What goes wrong:** Someone adds a toggle for the `status` segment (error + stale indicators).
**Why it happens:** Applying the toggle pattern uniformly to all segments.
**How to avoid:** The `status` segment should ALWAYS render — it shows error states and stale data indicators. These are operational health signals, not user preference segments.
**Warning signs:** Users not seeing error states when data source fails.

## Code Examples

Verified patterns from existing codebase:

### Reading Option with Default
```bash
# From render.sh — existing pattern
bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")
```

### Toggle Check Pattern
```bash
# Existing pattern from tmux-battery and tmux-cpu plugins
[[ "$(get_tmux_option "@claudux_show_weekly" "$CLAUDUX_DEFAULT_SHOW_WEEKLY")" == "on" ]] && render_weekly
```

### Setting tmux Options (user documentation)
```bash
# User sets options in .tmux.conf or live:
tmux set -g @claudux_show_weekly off
tmux set -g @claudux_show_email on
tmux set -g @claudux_bar_length 15
tmux set -g @claudux_warning_threshold 60
tmux set -g @claudux_critical_threshold 90
tmux set -g @claudux_refresh_interval 120
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| tmux status bar plugins as sed pipelines | Bash parameter expansion (tmux-battery pattern) | ~2020 | Already adopted by this project in claudux.tmux |
| Per-script config files | tmux global options (`show-option -gqv`) | Standard since tmux 1.8 | Already adopted — no migration needed |

**Deprecated/outdated:**
- None relevant. tmux option API has been stable for years.

## Open Questions

1. **`@claudux_mode` override option**
   - What we know: Auto-detection works via `detect_mode.sh` (checks for Admin API key)
   - What's unclear: Whether users want manual override (e.g., force local mode even when API key exists)
   - Recommendation: Out of scope for Phase 6 per CONTEXT.md ("Claude's Discretion"). Could be added later if users request it. Not required by any CONF-* requirement.

2. **Debug logging for configuration issues**
   - What we know: Currently no logging mechanism exists
   - What's unclear: Whether tmux plugin debugging is common enough to warrant a log level option
   - Recommendation: Out of scope for Phase 6. If needed, a `@claudux_debug "on"` option could write to `/tmp/claudux.log` in a future phase.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `scripts/claudux.sh`, `scripts/helpers.sh`, `scripts/render.sh`, `scripts/cache.sh`, `config/defaults.sh`, `claudux.tmux` — direct file reads
- tmux `show-option` man page — confirms `-gqv` flag behavior for global option reading

### Secondary (MEDIUM confidence)
- tmux-battery plugin pattern — confirmed via training data (parameter expansion for format strings, `show-option -gqv` for option reading)
- tmux-cpu plugin pattern — same conventions for toggle options ("on"/"off" strings)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - pure Bash, no new dependencies, all infrastructure exists
- Architecture: HIGH - single file change (dispatcher), one optional improvement (clamping)
- Pitfalls: HIGH - pitfalls are well-understood Bash/tmux issues with clear mitigations

**Research date:** 2026-03-10
**Valid until:** No expiry — tmux option API is stable, project conventions are established
