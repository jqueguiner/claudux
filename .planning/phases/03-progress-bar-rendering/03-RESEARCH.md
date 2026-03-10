# Phase 3: Progress Bar Rendering - Research

**Researched:** 2026-03-10
**Domain:** Bash/tmux progress bar rendering with Unicode and ANSI color
**Confidence:** HIGH

## Summary

Phase 3 converts normalized cache data (from Phase 2's `cache.json`) into tmux-formatted progress bar strings using Unicode block characters and color coding. The domain is narrow and well-understood: bash string manipulation, tmux format syntax, and Unicode block characters. No external libraries are needed — this is pure bash with `jq` for JSON parsing.

The cache schema is already established: `weekly.used`, `weekly.limit`, `monthly.used`, `monthly.limit`, `models.sonnet.used`, `models.sonnet.limit`, `models.opus.used`, `models.opus.limit`. The render functions compute percentage from `used/limit`, map it to filled/empty block characters, apply color via tmux `#[fg=colourN]` syntax, and output self-contained labeled strings.

**Primary recommendation:** Create a single `scripts/render.sh` with a core `render_bar` function and four thin wrappers (`render_weekly`, `render_monthly`, `render_model_sonnet`, `render_model_opus`) that read cache and call `render_bar`. Keep color logic inside `render_bar` for single-point-of-change. Handle edge cases (0%, 100%, missing cache, limit=0) defensively.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Use Unicode block characters for smooth, partial-fill bars:
  - Full block: `█` (U+2588) for filled segments
  - Light shade: `░` (U+2591) for empty segments
  - No partial blocks (U+2589-U+258F) — tmux miscalculates width for some terminals
- Stick to single-width characters only
- Format: `[██████░░░░]` with surrounding brackets for visual containment
- Bar length: read from `@claudux_bar_length` (default 10 chars from defaults.sh)
- Use tmux `#[fg=colourN]` syntax for 256-color support (not true color)
- Three tiers: Green (`colour34`) < warning, Yellow (`colour220`) warning-critical, Red (`colour196`) >= critical
- Thresholds read from `@claudux_warning_threshold` and `@claudux_critical_threshold`
- Reset color after each segment with `#[default]`
- Label format: `LABEL: [████░░░░░░] XX%`
- Labels: W (weekly), M (monthly), S (sonnet), O (opus)
- Percentage: integer, no decimal
- When usage is 0%: show empty bar `[░░░░░░░░░░] 0%`
- When usage >= 100%: show full bar in red `[██████████] 100%`
- New script: `scripts/render.sh` with functions: `render_bar`, `render_weekly`, `render_monthly`, `render_model_sonnet`, `render_model_opus`
- Each render_* function reads cache via `cache_read`, extracts field via `jq`, calls `render_bar`
- When cache is missing or has error: output nothing (error display is Phase 4)
- Single space between bars when composed, no pipe/slash separators

### Claude's Discretion
- Exact colour numbers if the specified ones don't look right across terminals
- Whether to add a subtle dim color for the label text
- Rounding behavior for edge cases (e.g., 0.4% → 0% or 1%)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DISP-01 | User sees weekly consumption quota as a progress bar in the tmux status bar | `render_weekly` reads `weekly.used`/`weekly.limit` from cache, calls `render_bar` to produce `W: [████░░░░░░] XX%` |
| DISP-02 | User sees monthly consumption quota as a progress bar in the tmux status bar | `render_monthly` reads `monthly.used`/`monthly.limit` from cache, same pattern |
| DISP-03 | User sees Sonnet-specific usage as a dedicated progress bar | `render_model_sonnet` reads `models.sonnet.used`/`models.sonnet.limit` from cache |
| DISP-04 | User sees Opus-specific usage as a dedicated progress bar | `render_model_opus` reads `models.opus.used`/`models.opus.limit` from cache |
| DISP-07 | Progress bars use color coding for urgency (green < 50%, yellow 50-80%, red > 80%) | `render_bar` applies `#[fg=colour34]` / `#[fg=colour220]` / `#[fg=colour196]` based on percentage vs thresholds |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 4.0+ | Script execution | Already required by tmux plugin ecosystem; project uses `#!/usr/bin/env bash` |
| jq | 1.6+ | JSON field extraction from cache.json | Already a project dependency (Phase 1 `check_deps.sh`) |
| tmux | 3.0+ | Color format strings `#[fg=colourN]` | Target platform; 256-color support reliable since tmux 2.0 |
| printf | builtin | String construction | Avoids `echo` portability issues with escape sequences |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `bc` or bash arithmetic | Percentage calculation | Bash `$(( ))` integer arithmetic sufficient; no floating point needed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| tmux `#[fg=colourN]` | ANSI `\033[38;5;Nm` | ANSI codes add character width to tmux status bar calculations; tmux format syntax is zero-width |
| `█░` block chars | `#-` ASCII chars | Less visual polish but zero Unicode risk; user locked in Unicode blocks |
| `jq` for JSON | `grep`/`sed` parsing | Fragile; jq is already a dependency |

## Architecture Patterns

### Script Structure
```
scripts/
├── render.sh          # NEW — all rendering functions (this phase)
├── cache.sh           # EXISTS — cache_read() provides input data
├── helpers.sh         # EXISTS — get_tmux_option() for config
├── fetch.sh           # EXISTS — data fetch (Phase 2)
└── ...
```

### Pattern 1: Source Chain
**What:** Each script sources `helpers.sh` at top, then any needed peers.
**When to use:** Always — established project pattern.
**Example:**
```bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/cache.sh"
```

### Pattern 2: Function-per-Segment (tmux-battery style)
**What:** Each displayable segment is a self-contained function that reads its own data, renders, and outputs a complete tmux-formatted string.
**When to use:** For each bar type (weekly, monthly, sonnet, opus).
**Example:**
```bash
render_weekly() {
    local cache_data
    cache_data=$(cache_read) || return 0  # Silent on missing cache

    local used limit pct
    used=$(printf '%s' "$cache_data" | jq -r '.weekly.used // 0')
    limit=$(printf '%s' "$cache_data" | jq -r '.weekly.limit // 0')

    # Skip if limit is 0 (unknown)
    [[ "$limit" -eq 0 ]] && return 0

    pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100

    local bar_length
    bar_length=$(get_tmux_option "@claudux_bar_length" "$CLAUDUX_DEFAULT_BAR_LENGTH")

    printf 'W: %s %d%%' "$(render_bar "$pct" "$bar_length")" "$pct"
}
```

### Pattern 3: Core Renderer with Color Logic
**What:** A single `render_bar` function handles all visual construction — filled chars, empty chars, color selection.
**When to use:** Called by every `render_*` wrapper.
**Example:**
```bash
render_bar() {
    local pct="$1"
    local bar_length="${2:-10}"

    local filled=$(( (pct * bar_length + 50) / 100 ))  # Round to nearest
    local empty=$(( bar_length - filled ))

    # Color selection based on thresholds
    local warning_threshold critical_threshold color
    warning_threshold=$(get_tmux_option "@claudux_warning_threshold" "$CLAUDUX_DEFAULT_WARNING_THRESHOLD")
    critical_threshold=$(get_tmux_option "@claudux_critical_threshold" "$CLAUDUX_DEFAULT_CRITICAL_THRESHOLD")

    if [[ $pct -ge $critical_threshold ]]; then
        color="colour196"  # Red
    elif [[ $pct -ge $warning_threshold ]]; then
        color="colour220"  # Yellow
    else
        color="colour34"   # Green
    fi

    # Build bar string
    local bar="[#[fg=${color}]"
    local i
    for (( i = 0; i < filled; i++ )); do bar+="█"; done
    bar+="#[default]"
    for (( i = 0; i < empty; i++ )); do bar+="░"; done
    bar+="]"

    printf '%s' "$bar"
}
```

### Anti-Patterns to Avoid
- **Calling `get_tmux_option` inside loops:** Read thresholds once per function call, not per character. tmux option reads fork a process.
- **Using `echo -e` for Unicode:** Portability varies. Use `printf '%s'` with literal Unicode characters.
- **Reading cache multiple times in one render cycle:** Read once, parse multiple fields from the same string.
- **Floating-point arithmetic in bash:** Bash cannot do float math. Use `$(( used * 100 / limit ))` integer math. For rounding, use `$(( (used * 100 + limit/2) / limit ))`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | `grep`/`sed` on cache.json | `jq -r '.field'` | Cache JSON has nested objects; regex parsing is fragile |
| Color selection | Inline if/else in every render function | Central `render_bar` function | Single-point-of-change for threshold logic |
| tmux option reads | Direct `tmux show-option` calls | `get_tmux_option` from helpers.sh | Already handles fallback defaults and error suppression |

**Key insight:** The rendering logic itself is simple — the complexity is in edge cases (missing cache, limit=0, overflow) not in the bar construction.

## Common Pitfalls

### Pitfall 1: Division by Zero When Limit is 0
**What goes wrong:** Org mode cache has `"limit": 0` because the Admin API doesn't expose tier limits. `$(( used * 100 / 0 ))` crashes bash.
**Why it happens:** The org API reports usage but not quota caps.
**How to avoid:** Guard with `[[ "$limit" -eq 0 ]] && return 0` — output nothing when limit is unknown. Phase 4 or Phase 6 may add a way for users to set manual limits.
**Warning signs:** Error messages about arithmetic in tmux status bar.

### Pitfall 2: tmux Format String Width Miscalculation
**What goes wrong:** tmux counts `#[fg=colourN]` as zero-width (correct), but if you accidentally use raw ANSI escape codes (`\033[...`), tmux counts them as visible characters and the status bar layout breaks.
**Why it happens:** Mixing tmux format syntax with ANSI escapes.
**How to avoid:** Always use `#[fg=colourN]` and `#[default]`, never raw ANSI codes. Test that bar output doesn't shift neighboring status bar elements.
**Warning signs:** Status bar elements overlap or have unexpected gaps.

### Pitfall 3: Unicode Width in Terminals
**What goes wrong:** Some terminals (especially older ones) render `█` as double-width or substitute a replacement character.
**Why it happens:** Unicode East Asian Width ambiguity. Block characters are "Ambiguous" width.
**How to avoid:** Stick to `█` (U+2588) and `░` (U+2591) which are single-width in all modern terminals (iTerm2, Alacritty, kitty, GNOME Terminal, Windows Terminal). The user locked this decision — no partial blocks.
**Warning signs:** Bars appear too wide or characters are replaced with `?`.

### Pitfall 4: Percentage Rounding Edge Cases
**What goes wrong:** `used=1, limit=200` → `$(( 1 * 100 / 200 ))` = 0, but filled should arguably be 1 character for visual feedback.
**Why it happens:** Integer truncation in bash arithmetic.
**How to avoid:** Use rounding: `$(( (pct * bar_length + 50) / 100 ))` for nearest-integer. For percentage display, `$(( (used * 100 + limit/2) / limit ))` — but cap display at 0% minimum and 100% maximum.
**Warning signs:** Bar shows 0% with some usage, or shows 100% when not quite full.

### Pitfall 5: Stale `cache_read` Data During Render
**What goes wrong:** If cache is being written while render reads, you get partial JSON.
**Why it happens:** Race condition between `fetch.sh` (write) and `render.sh` (read).
**How to avoid:** Phase 1's `cache_write` already uses atomic tmpfile+mv, so `cache_read` always gets a complete file. No additional locking needed for reads.
**Warning signs:** `jq` parse errors in status bar output.

## Code Examples

### Cache JSON Schema (Input to Render)
```json
{
  "mode": "org",
  "fetched_at": 1710072000,
  "account": {"email": "user@example.com"},
  "weekly": {"used": 2500000, "limit": 5000000, "unit": "tokens", "reset_at": 1710374400},
  "monthly": {"used": 8000000, "limit": 20000000, "unit": "tokens", "reset_at": 1712534400},
  "models": {
    "sonnet": {"used": 1500000, "limit": 0, "unit": "tokens", "reset_at": 0},
    "opus": {"used": 1000000, "limit": 0, "unit": "tokens", "reset_at": 0}
  },
  "error": null
}
```

### Expected Output Examples
```
W: [#[fg=colour34]█████#[default]░░░░░] 50%
M: [#[fg=colour34]████#[default]░░░░░░] 40%
S: [#[fg=colour220]███████#[default]░░░] 70%
O: [#[fg=colour196]█████████#[default]░] 92%
```

### tmux Color Format Pattern
```bash
# tmux interprets #[...] as zero-width format directives
# fg=colourN uses 256-color palette (0-255)
# #[default] resets all attributes

"#[fg=colour34]text#[default]"   # Green text, then reset
"#[fg=colour220]text#[default]"  # Yellow text, then reset
"#[fg=colour196]text#[default]"  # Red text, then reset
```

### Integer Percentage Calculation in Bash
```bash
# Safe percentage with overflow cap
local pct
if [[ "$limit" -gt 0 ]]; then
    pct=$(( (used * 100) / limit ))
    [[ $pct -gt 100 ]] && pct=100
    [[ $pct -lt 0 ]] && pct=0
else
    pct=0
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ANSI escape codes in tmux | tmux `#[fg=...]` format syntax | tmux 1.0+ | Zero-width color directives, proper status bar layout |
| ASCII `[####----]` bars | Unicode `[████░░░░]` bars | Terminal Unicode support matured ~2020 | Better visual density and readability |
| `tput` color commands | Direct `#[fg=colourN]` | N/A for tmux plugins | `tput` doesn't work inside tmux format strings |

**Deprecated/outdated:**
- True color (`#[fg=#RRGGBB]`) in tmux: Works in tmux 3.2+ but not all terminals pass it through. 256-color is safer.

## Open Questions

1. **Model-level limits unknown for org mode**
   - What we know: Admin API returns `used` tokens per model but no `limit`. Cache stores `"limit": 0`.
   - What's unclear: Whether to show model bars when limit is 0, or silently hide them.
   - Recommendation: When `limit` is 0, output nothing. The wrapper returns early. Users in org mode will see weekly/monthly bars but may not see model bars unless limits are added in a future phase.

2. **Label dimming**
   - What we know: User left label color as "Claude's Discretion."
   - Recommendation: Use `#[fg=colour245]` (medium gray) for labels, so the colored bar stands out. This is a subtle visual improvement that doesn't change the layout. Example: `#[fg=colour245]W:#[default] [...]`

## Sources

### Primary (HIGH confidence)
- Project codebase: `scripts/cache.sh`, `scripts/helpers.sh`, `config/defaults.sh` — established patterns
- Project codebase: `scripts/api_fetch.sh`, `scripts/local_parse.sh` — cache JSON schema
- tmux man page: `#[fg=colourN]` format string syntax

### Secondary (MEDIUM confidence)
- Unicode Consortium: Block Elements U+2580-U+259F character properties
- tmux-battery, tmux-cpu plugins — self-contained segment output pattern

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pure bash + jq, no external dependencies to verify
- Architecture: HIGH — follows existing project patterns exactly
- Pitfalls: HIGH — identified from cache schema analysis and tmux format string behavior

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable domain, no fast-moving dependencies)
