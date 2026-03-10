# Phase 5: Plugin Integration - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire all existing components into a working tmux plugin. Update claudux.tmux from stub to full TPM entry point with format string registration. Create dispatcher script that routes format string calls to render functions. Implement background cache refresh. Support both TPM and manual git clone installation. No new rendering or data logic — just integration.

</domain>

<decisions>
## Implementation Decisions

### Format string names
- Register these `#{claudux_*}` format strings via sed substitution in claudux.tmux:
  - `#{claudux_weekly}` → weekly progress bar with label
  - `#{claudux_monthly}` → monthly progress bar with label
  - `#{claudux_sonnet}` → Sonnet model bar with label
  - `#{claudux_opus}` → Opus model bar with label
  - `#{claudux_reset}` → reset countdown
  - `#{claudux_email}` → account email
  - `#{claudux_status}` → error indicator (if error) or stale indicator (if stale), empty otherwise
- Users compose these freely in `status-right` / `status-left`
- Example user config: `set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset} #{claudux_status}'`

### Dispatcher script
- New script: `scripts/claudux.sh` — single dispatcher called by all format strings
- Takes segment name as argument: `claudux.sh weekly`, `claudux.sh reset`, etc.
- Flow:
  1. Source helpers.sh, cache.sh, render.sh
  2. Trigger background refresh if cache is stale (non-blocking)
  3. Route to appropriate render_* function based on argument
  4. Output the rendered string
- Each format string resolves to: `#($PLUGIN_DIR/scripts/claudux.sh SEGMENT_NAME)`
- Single script = single source/load, shared cache read — avoids N separate script forks

### Format string registration (claudux.tmux)
- Follow tmux-battery pattern exactly:
  1. Read current `status-right` and `status-left` values
  2. For each `#{claudux_*}` placeholder found:
     - Replace with `#($CURRENT_DIR/scripts/claudux.sh SEGMENT_NAME)`
  3. Write modified values back with `tmux set-option`
- Use `sed` for substitution — standard, no dependencies
- Also set `status-right-length` to 200 (default 40 is too short for multiple bars)

### Background cache refresh
- When dispatcher detects stale cache: spawn `fetch.sh` in background via `tmux run-shell -b`
- Only spawn if not already running (check PID file at `$CACHE_DIR/fetch.pid`)
- fetch.sh already handles locking (from Phase 1) — prevents duplicate fetches
- On first plugin load (claudux.tmux), trigger initial fetch: `tmux run-shell -b "$CURRENT_DIR/scripts/fetch.sh"`

### Manual install support
- Works without TPM — user adds to tmux.conf:
  ```
  run-shell ~/.tmux/plugins/claudux/claudux.tmux
  ```
- Same entry point, same behavior
- Document in README (Phase 7)

### tmux status-interval consideration
- Don't override user's `status-interval` — respect their setting
- Document recommended value (5-15 seconds) in README
- The cache TTL (default 300s) means API calls happen every 5 min regardless of status-interval

### Claude's Discretion
- Exact sed regex for format string substitution
- Whether to set status-right-length or just document it
- PID file cleanup strategy (on tmux server exit)
- Order of format string registration (shouldn't matter but implementation detail)

</decisions>

<specifics>
## Specific Ideas

- Research confirmed: tmux-battery pattern uses sed replacement of `#{plugin_var}` with `#(path/to/script arg)` — follow this exactly
- Single dispatcher script avoids the "separate API call per segment" anti-pattern from PITFALLS.md
- Keep claudux.tmux minimal — registration only, no business logic
- User emphasized modularity — dispatcher delegates to render functions, never duplicates logic

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `claudux.tmux`: stub exists, sources helpers.sh and runs check_deps.sh — extend, don't rewrite
- `scripts/render.sh`: 8 render_* functions ready to call (weekly, monthly, model_sonnet, model_opus, reset, email, stale_indicator, error)
- `scripts/fetch.sh`: orchestrator for data refresh, already handles lock/detect/fetch/cache
- `scripts/cache.sh`: is_cache_stale() for triggering background refresh
- `scripts/helpers.sh`: get_tmux_option(), set_tmux_option() for reading/writing tmux options

### Established Patterns
- All scripts source helpers.sh first
- Cache reads via cache_read() — render functions already do this
- Lock-based concurrency via acquire_lock()/release_lock()
- Non-blocking operations preferred (check_deps warns, doesn't crash)

### Integration Points
- `claudux.tmux` → registers format strings → each resolves to `claudux.sh SEGMENT`
- `claudux.sh` → sources render.sh → calls render_* functions
- `claudux.sh` → checks is_cache_stale() → spawns fetch.sh in background
- `fetch.sh` → detect_mode → api_fetch or local_parse → cache_write

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-plugin-integration*
*Context gathered: 2026-03-10*
