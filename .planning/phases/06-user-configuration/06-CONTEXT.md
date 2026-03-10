# Phase 6: User Configuration - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Make all `@claudux_*` tmux options work end-to-end. Add show/hide toggling to the dispatcher so users can control which segments appear. Ensure threshold, bar length, and refresh interval options take effect. No new rendering functions — just configuration wiring.

</domain>

<decisions>
## Implementation Decisions

### Show/hide toggle behavior
- When `@claudux_show_weekly` is "off": dispatcher outputs nothing for `weekly` segment
- Same for `show_monthly`, `show_model`, `show_reset`, `show_email`
- Implementation: add toggle check in dispatcher before calling render function
- `@claudux_show_model` controls BOTH Sonnet and Opus bars (single toggle, not per-model)
- Default values already defined in `config/defaults.sh` — just wire them into dispatcher

### Toggle option names (final list)
- `@claudux_show_weekly` — show/hide weekly bar (default: "on")
- `@claudux_show_monthly` — show/hide monthly bar (default: "on")
- `@claudux_show_model` — show/hide Sonnet and Opus bars (default: "on")
- `@claudux_show_reset` — show/hide reset countdown (default: "on")
- `@claudux_show_email` — show/hide account email (default: "off")
- Values: "on" or "off" — standard tmux option convention

### Threshold configuration
- `@claudux_warning_threshold` — yellow threshold percentage (default: 50)
- `@claudux_critical_threshold` — red threshold percentage (default: 80)
- Already read by `render_bar()` in render.sh via `get_tmux_option` — no new wiring needed
- Just verify end-to-end: user sets option → next status refresh reflects new threshold

### Bar length configuration
- `@claudux_bar_length` — number of characters in progress bar (default: 10)
- Already read by each `render_*` function via `get_tmux_option` — no new wiring needed
- Valid range: 5-30 (clamp if out of bounds in render_bar)

### Refresh interval configuration
- `@claudux_refresh_interval` — cache TTL in seconds (default: 300)
- Already read by `is_cache_stale()` in cache.sh — no new wiring needed
- User changes take effect on next staleness check (no restart needed)

### Where configuration changes happen
- Only the dispatcher (`claudux.sh`) needs modification — add toggle checks
- render.sh and cache.sh already read their options via get_tmux_option
- No new scripts needed
- defaults.sh already has all default values defined

### Claude's Discretion
- Whether to add input validation (e.g., clamp bar_length to 5-30)
- Whether to add a `@claudux_mode` override option ("org"/"local"/"auto")
- Log level for debugging configuration issues

</decisions>

<specifics>
## Specific Ideas

- Minimal change: most config already works — Phase 6 is primarily wiring show/hide toggles into the dispatcher
- Keep it simple: "on"/"off" strings, not booleans — tmux options are always strings
- Don't add new options beyond what REQUIREMENTS.md specifies — CONF-01 through CONF-05

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/claudux.sh`: dispatcher with case routing — add toggle checks before each render call
- `scripts/helpers.sh`: `get_tmux_option()` — already supports fallback defaults
- `config/defaults.sh`: all 9 CLAUDUX_DEFAULT_* constants defined
- `scripts/render.sh`: render_bar() already reads thresholds and bar_length

### Established Patterns
- Option reading: `get_tmux_option "@claudux_option_name" "$CLAUDUX_DEFAULT_VALUE"`
- Toggle check: `[[ "$(get_tmux_option "@claudux_show_X" "$DEFAULT")" == "on" ]]`
- All options are tmux global options — no config files for user settings

### Integration Points
- Modify `scripts/claudux.sh` — add toggle guards before render calls
- Optionally add bar_length clamping in `scripts/render.sh` render_bar()
- No other files need changes — config reading is already wired

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-user-configuration*
*Context gathered: 2026-03-10*
