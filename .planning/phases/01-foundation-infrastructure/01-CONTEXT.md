# Phase 1: Foundation Infrastructure - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Secure, cached, cross-platform substrate that all other components build on. Delivers: helpers, cache system with atomic writes and TTL, API key security, cross-platform detection, dependency checker, and default configuration values. No rendering, no API calls, no tmux format strings — just the foundation.

</domain>

<decisions>
## Implementation Decisions

### Directory structure
- Follow the tmux-battery/tmux-cpu convention exactly:
  - `claudux.tmux` — TPM entry point (stub in this phase)
  - `scripts/` — all executable scripts
  - `scripts/helpers.sh` — shared utilities (get_tmux_option, platform detection, path resolution)
  - `scripts/cache.sh` — cache read/write/TTL operations
  - `scripts/check_deps.sh` — dependency checker (jq, curl, tmux version)
  - `config/defaults.sh` — default option values, sourced by helpers.sh
- Keep it flat within `scripts/` — no subdirectories unless complexity demands it later

### Cache location and format
- Cache directory: `${XDG_CACHE_HOME:-$HOME/.cache}/claudux/`
- Cache file: `cache.json` — single JSON file, all data sources write to the same format
- TTL: configurable via `@claudux_refresh_interval`, default 300 seconds (5 min)
- Stale detection: compare file mtime to current time using platform-appropriate `stat`
- Atomic writes: write to `cache.json.tmp` then `mv` to `cache.json` — prevents partial reads
- Lock file: use `flock` on Linux, fallback to mkdir-based lock on macOS (flock unavailable on BSD)

### API key security
- Primary: `$ANTHROPIC_ADMIN_API_KEY` environment variable
- Secondary: `~/.config/claudux/credentials` file with `chmod 600`
- Never pass key as CLI argument (visible in `ps aux`)
- Ship `.gitignore` covering `~/.config/claudux/credentials` pattern
- Key type detection: check `sk-ant-admin` prefix → org mode; absence → local mode
- Clear error messages when key is missing or wrong type

### Cross-platform strategy
- Platform detection function in helpers.sh: `uname -s` → Linux or Darwin
- `stat` for mtime: Linux uses `stat -c %Y`, macOS uses `stat -f %m`
- `date` for epoch: Linux uses `date +%s`, macOS uses `date +%s` (both work)
- All scripts use `#!/usr/bin/env bash` shebang (not `/bin/bash`)
- Target: Bash 4.0+ (macOS ships 3.2, but Homebrew bash is 5.x — document this)

### Dependency checker
- Check at plugin load time (in claudux.tmux stub): jq, curl, bash version
- If jq missing: display tmux message "claudux: jq required — install with brew/apt"
- If bash too old: display tmux message with upgrade instructions
- Non-blocking: warn but don't crash tmux

### Default configuration values
- All defaults in `config/defaults.sh`, sourced by helpers.sh
- `@claudux_refresh_interval`: 300 (seconds)
- `@claudux_bar_length`: 10 (characters)
- `@claudux_warning_threshold`: 50 (percent)
- `@claudux_critical_threshold`: 80 (percent)
- `@claudux_show_weekly`: "on"
- `@claudux_show_monthly`: "on"
- `@claudux_show_model`: "on"
- `@claudux_show_reset`: "on"
- `@claudux_show_email`: "off" (privacy default)
- Helper function `get_tmux_option` reads tmux option with fallback to default

### Claude's Discretion
- Exact error message wording
- Whether to use color in dependency check warnings
- Internal logging approach (stderr, log file, or tmux display-message)
- Specific `flock` vs `mkdir` lock implementation details

</decisions>

<specifics>
## Specific Ideas

- User emphasized "pragmatic, not over-engineered" — keep helpers minimal, don't abstract prematurely
- "Design for realistic open-source scaling" — follow TPM conventions so the plugin feels native
- "Clarity, modularity, maintainability" — each script should have a single responsibility, be readable standalone
- Research identified tmux-battery as the canonical pattern to follow

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield repository

### Established Patterns
- None yet — this phase establishes the patterns all subsequent phases follow

### Integration Points
- `claudux.tmux` will be the TPM entry point (stub only in this phase)
- `helpers.sh` will be sourced by every other script
- `cache.sh` will be called by the data source scripts (Phase 2) and read by renderer (Phase 3)
- `config/defaults.sh` will be the single source of truth for default values

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation-infrastructure*
*Context gathered: 2026-03-10*
