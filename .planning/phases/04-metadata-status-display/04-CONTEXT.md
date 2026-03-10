# Phase 4: Metadata & Status Display - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Render contextual metadata alongside progress bars: quota reset countdowns, account email, stale data indicator, and error state display. Extends render.sh with new functions following the same pattern as Phase 3. No format string registration (Phase 5), no configuration toggling (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Reset countdown format
- Display as relative time: `⏱ Xh Ym` (hours and minutes until reset)
- When reset is > 24h away: `⏱ Xd Yh` (days and hours)
- When reset is < 1h: `⏱ Xm` (minutes only)
- When reset time is unknown/missing: output nothing (silent return)
- Use a simple clock symbol `⏱` — single-width, renders reliably in tmux
- Actually, to be safe with tmux Unicode width: use text-only `R:` label instead, matching the W/M/S/O pattern
- Format: `#[fg=colour245]R:#[default] 2h 15m`
- Read `reset_at` from cache.json weekly and monthly sections
- Show only the nearest reset time (whichever comes sooner)

### Account email display
- Format: `#[fg=colour245]email#[default]` — just the email, dimmed
- Truncate long emails: show first 20 chars + `…` if longer
- Read from `cache.json` → `account.email`
- When email is null/missing: output nothing (local mode may not have email)

### Stale data indicator
- When cache mtime > 2x refresh interval: append `?` to the end of rendered output
- Color the `?` in dim yellow: `#[fg=colour136]?#[default]`
- This isn't a standalone segment — it modifies the output of other render functions
- Approach: add `render_stale_indicator` function that returns `?` or empty string
- The dispatcher (Phase 5) will append this to composed output
- Stale threshold: `2 * @claudux_refresh_interval` (default: 2 * 300 = 600 seconds)

### Error state display
- When cache has `error` field non-null: show error indicator instead of bars
- Format: `#[fg=colour196][!]#[default]` — red exclamation in brackets
- Followed by short error code: `#[fg=colour196][!] auth_failed#[default]`
- Error codes from cache schema: `auth_failed`, `rate_limited`, `api_error`, `no_source`, `parse_error`
- When error is present, all progress bar render functions already return empty (Phase 3 handles this)
- Add `render_error` function: reads cache error, outputs indicator
- The dispatcher (Phase 5) will call `render_error` first — if it outputs anything, skip progress bars

### Claude's Discretion
- Exact time rounding behavior (round minutes up or down)
- Email truncation threshold (20 chars suggested but flexible)
- Whether to log detailed error messages to a file alongside the short indicator

</decisions>

<specifics>
## Specific Ideas

- Follow render.sh's pattern exactly: source helpers.sh + cache.sh, read via cache_read(), extract via jq
- Labels consistent with Phase 3: dim colour245, single-letter where possible
- User wants reset dates with "hour associated" — the relative countdown handles this
- Keep error display minimal — status bar space is precious

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/render.sh`: established render_* pattern — source cache.sh, read cache, extract jq, format tmux string
- `scripts/cache.sh`: `cache_read()`, `is_cache_stale()` — both needed for this phase
- `scripts/helpers.sh`: `get_tmux_option()`, `get_file_mtime()` — for stale detection config
- `config/defaults.sh`: `CLAUDUX_DEFAULT_REFRESH_INTERVAL=300` — base for stale threshold calc

### Established Patterns
- Dim label: `#[fg=colour245]LABEL:#[default]`
- Silent return on missing/error data: `return 0` without output
- Cache error check: `jq -e '.error == null'`
- All render functions are self-contained segments

### Integration Points
- New functions added to `scripts/render.sh` (extend, don't create new file)
- `render_error` will be checked by dispatcher (Phase 5) before calling progress bar renders
- `render_stale_indicator` will be appended by dispatcher after composed output
- `render_reset` reads `reset_at` timestamps from cache.json
- `render_email` reads `account.email` from cache.json

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-metadata-status-display*
*Context gathered: 2026-03-10*
