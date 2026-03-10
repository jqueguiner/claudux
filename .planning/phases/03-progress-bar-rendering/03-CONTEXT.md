# Phase 3: Progress Bar Rendering - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Render quota consumption as color-coded progress bars for display in the tmux status bar. Takes normalized cache data (from Phase 2) and outputs tmux-formatted strings with Unicode progress bars, percentage labels, and color coding. Covers weekly, monthly, Sonnet, and Opus bars. No tmux format string registration (Phase 5), no configuration toggling (Phase 6) — just the rendering functions.

</domain>

<decisions>
## Implementation Decisions

### Progress bar style
- Use Unicode block characters for smooth, partial-fill bars:
  - Full block: `█` (U+2588) for filled segments
  - Light shade: `░` (U+2591) for empty segments
  - No partial blocks (U+2589-U+258F) — tmux miscalculates width for some terminals
- Stick to single-width characters only — research confirmed tmux Unicode width bugs with multi-byte chars
- Format: `[██████░░░░]` with surrounding brackets for visual containment
- Bar length: read from `@claudux_bar_length` (default 10 chars from defaults.sh)

### Color scheme
- Use tmux `#[fg=colourN]` syntax for 256-color support (not true color — wider compatibility)
- Three tiers based on usage percentage:
  - Green (`colour34`): usage < warning threshold (default 50%)
  - Yellow (`colour220`): usage >= warning and < critical threshold (default 50-80%)
  - Red (`colour196`): usage >= critical threshold (default 80%)
- Thresholds read from `@claudux_warning_threshold` and `@claudux_critical_threshold`
- Reset color after each segment with `#[default]` to avoid color bleeding

### Label format
- Each bar shows: `LABEL: [████░░░░░░] XX%`
- Labels:
  - Weekly bar: `W` (short for tmux status bar space)
  - Monthly bar: `M`
  - Sonnet bar: `S`
  - Opus bar: `O`
- Percentage: integer, no decimal (saves space, precision not meaningful)
- When usage is 0%: show empty bar `[░░░░░░░░░░] 0%`
- When usage >= 100%: show full bar in red `[██████████] 100%`

### Render script structure
- New script: `scripts/render.sh` — all rendering functions
- Functions:
  - `render_bar <percentage> <bar_length>` — returns colored progress bar string
  - `render_weekly` — reads cache, renders weekly bar with label
  - `render_monthly` — reads cache, renders monthly bar with label
  - `render_model_sonnet` — reads cache, renders Sonnet bar with label
  - `render_model_opus` — reads cache, renders Opus bar with label
- Each `render_*` function:
  1. Reads cache.json via `cache_read` (from cache.sh)
  2. Extracts relevant field via `jq`
  3. Calls `render_bar` for the visual
  4. Outputs complete tmux-formatted string
- When cache is missing or has error: output nothing (error display is Phase 4)

### Separator between bars
- Use a single space between multiple bars when composed in status bar
- No pipe/slash separators — let the color changes provide visual separation
- Individual render functions output self-contained segments (label + bar + percentage)

### Claude's Discretion
- Exact colour numbers if the specified ones don't look right across terminals
- Whether to add a subtle dim color for the label text
- Rounding behavior for edge cases (e.g., 0.4% → 0% or 1%)

</decisions>

<specifics>
## Specific Ideas

- Research warned: avoid emoji in tmux status bar — confirmed, stick to block characters only
- User wants "progress bars" specifically — not just percentages or sparklines
- Short labels (W/M/S/O) keep the status bar compact — user didn't ask for verbose labels
- Follow tmux-battery pattern: each segment is a self-contained output string

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/cache.sh`: `cache_read()` — reads cache.json content, returns 1 if missing
- `scripts/helpers.sh`: `get_tmux_option()` — read bar length, thresholds from tmux options
- `config/defaults.sh`: `CLAUDUX_DEFAULT_BAR_LENGTH=10`, `CLAUDUX_DEFAULT_WARNING_THRESHOLD=50`, `CLAUDUX_DEFAULT_CRITICAL_THRESHOLD=80`

### Established Patterns
- Source helpers.sh at top: `source "$CURRENT_DIR/helpers.sh"`
- Cache reads via `cache_read` — never read cache.json directly
- All config via `get_tmux_option` with fallback to defaults.sh constants

### Integration Points
- Input: reads from `cache.json` (written by Phase 2's fetch.sh)
- Output: tmux-formatted strings consumed by dispatcher (Phase 5)
- Config: thresholds and bar length from `@claudux_*` tmux options (Phase 6 makes these configurable)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-progress-bar-rendering*
*Context gathered: 2026-03-10*
