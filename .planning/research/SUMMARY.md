# Project Research Summary

**Project:** Claudux (tmux status bar plugin for Claude API usage monitoring)
**Domain:** tmux plugin / CLI tooling / API monitoring
**Researched:** 2026-03-10
**Confidence:** HIGH

## Executive Summary

Claudux occupies a well-defined niche: a TPM-installable tmux plugin that surfaces Claude API usage as glanceable status bar segments. The ecosystem has clear conventions — every major tmux plugin (tmux-battery, tmux-cpu, tmux-powerline) is pure Bash with format string interpolation, file-based caching, and `@plugin_option` configuration. There are no competing tools that fill this niche properly; existing solutions are either standalone Python scripts, full TUIs, or platform-specific hacks. The recommended approach is to follow the tmux-battery pattern exactly: a `claudux.tmux` entry point that registers `#{claudux_*}` format strings backed by lightweight Bash scripts reading from a shared cache file.

The single most important architectural decision is the caching layer. tmux status bar refresh runs a forked shell process on every `status-interval` tick. Making an API call synchronously inside that process will freeze the terminal — this is not a hypothetical but a documented failure mode with known recovery cost (full architectural rewrite). The cache-first pattern must be the foundation, not a later optimization. Related to this: the Anthropic Usage API requires an Admin API key, not a standard key, and is unavailable to individual (non-organization) accounts. The plugin must support a graceful fallback — local Claude Code JSONL log parsing for individual developers — and detect key type at startup with a clear error message.

The biggest product risk is scope confusion around "quotas." The term means three different things in the Anthropic ecosystem: monthly API spend limits (accessible via Admin API), per-minute rate limits (accessible via response headers with any key), and Claude Pro/Max subscription usage hours (no documented programmatic endpoint as of March 2026). The project spec's reference to "weekly consumption quota" maps to the subscription segment, yet the primary tooling available is the Admin API for org/API users. The MVP recommendation is to target both user segments but lead with whatever data is reliably accessible — and to clearly label every display element so users know exactly what they are seeing.

## Key Findings

### Recommended Stack

The correct stack for a tmux plugin is minimal and conventional. Every canonical TPM plugin is pure Bash — this is not a stylistic preference but an ecosystem constraint enforced by startup performance (Bash + curl + jq cold-starts under 10ms; Python takes 50-200ms, Node 100-500ms, and those timings are felt directly as status bar stutter). The only non-standard dependency is `jq`, which is required for safely parsing Anthropic's nested JSON responses. All other tools (curl, bash, tmux) ship with every target platform.

**Core technologies:**
- Bash 4.0+ (POSIX-compatible): Plugin runtime — ecosystem convention, zero dependency, fastest startup
- tmux 3.0+: Host environment — format strings stable since 2.1; true color available since 3.2
- TPM (Tmux Plugin Manager): Distribution — de facto standard, no alternative with meaningful adoption
- curl 7.x/8.x: HTTP requests — universally available, supports custom headers needed for Admin API auth
- jq 1.6+: JSON parsing — the only safe approach for nested API responses; must be a declared dependency
- File-based cache (XDG_CACHE_HOME): API response caching — prevents status bar blocking and API hammering

Two data sources are needed due to the dual-user-segment problem. The Admin API (`/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`) serves organization API users with full quota and cost data. Local JSONL log parsing (`~/.claude/projects/*/sessions/*.jsonl`) serves individual Claude Code subscription users who lack Admin API access. Both modes write to the same cache format so the rendering layer is source-agnostic.

### Expected Features

FEATURES.md reveals the plugin serves two distinct user segments with different data sources and different quota concepts. The competitive landscape confirms no existing tool is a proper TPM plugin for this purpose — all competitors have critical limitations (Python dependencies, macOS-only, full TUI rather than status segment, manual install).

**Must have (table stakes):**
- Quota usage as progress bars — core value prop; Unicode block chars `\u2588-\u2591` for smooth bars
- Quota reset countdown — "resets in Xh Ym" relative format; second most-requested data point
- Auto-refresh with caching — foundation layer; without this, status bar either lags or hammers the API
- TPM compatibility — users expect `set -g @plugin 'user/claudux'` and `prefix + I`
- tmux format string interpolation — `#{claudux_weekly}`, `#{claudux_reset}`, etc. placed freely in status-left/right
- Color-coded status indicators — green/yellow/red thresholds; at-a-glance urgency
- Configurable display — `@claudux_show_*` options to toggle segments; per TPM convention
- Cross-platform (Linux + macOS) — GNU vs BSD stat/date portability required

**Should have (competitive differentiators):**
- Dual data source support (subscription OAuth + org Admin API) — no existing tool handles both
- Model-specific usage breakdown — Opus and Sonnet have separate limits; users hit Opus first
- Error state display — `[!]` indicator when auth fails or API is unreachable
- Stale data indicator — dim color or `?` suffix when cache exceeds 2x refresh interval
- Compact single-segment mode — `W:45% O:12% S:8% [2h]` for power users
- Spend tracking for API users — `$X.XX/$Y.00` from Cost Report endpoint

**Defer to v2+:**
- Background daemon for cache refresh — basic file-caching is sufficient for MVP; daemon adds complexity
- Claude Code statusLine hook integration — depends on Anthropic shipping quota data in statusLine JSON (issue #28999, not yet shipped)
- Subscription plan auto-detection — reduces user friction but adds complexity; require manual plan config at first
- Historical usage graphs — explicitly out of scope per PROJECT.md; Console already provides this
- Web dashboard, billing management, non-Claude providers — explicitly out of scope

### Architecture Approach

The architecture is a layered shell pipeline following the tmux-battery/tmux-cpu pattern exactly. The `.tmux` entry point performs format string registration (sed-replacing `#{claudux_*}` placeholders with `#(path/to/script.sh arg)` calls) at plugin load time. All status bar invocations call a single dispatcher script (`claudux.sh`) that reads from a shared cache file — never from the network directly. One background API call per TTL interval populates the cache; all segments share it.

**Major components:**
1. `claudux.tmux` — TPM entry point; format string registration via sed substitution into status-left/status-right
2. `scripts/claudux.sh` — Main dispatcher; receives segment name, checks cache freshness, delegates to api or cache, delegates to render
3. `scripts/api.sh` — Anthropic API client; curl wrapper with auth, error handling, JSON extraction via jq, writes to cache
4. `scripts/cache.sh` — File-based cache; TTL check via stat mtime, atomic writes (write to tmpfile + mv), XDG_CACHE_HOME path
5. `scripts/render.sh` — Output formatter; progress bar chars, tmux `#[fg=]` color codes, reset time formatting
6. `scripts/helpers.sh` — Shared utilities; `get_tmux_option` wrapper, platform detection, path resolution
7. `config/defaults.sh` — Default option values; sourced by helpers.sh

Build order follows dependency layers: helpers/defaults -> cache -> api -> render -> claudux.sh -> claudux.tmux -> polish. Each layer can be tested in isolation before wiring together.

### Critical Pitfalls

1. **Admin API key vs standard key confusion** — The Usage and Cost API requires `sk-ant-admin...` prefix; standard keys return 401/403. Detect key prefix at startup, show clear error, document the Admin Key provisioning path in README. Provide rate-limit-header fallback mode for users without Admin access.

2. **Blocking API calls in status bar** — Synchronous curl in `#(...)` freezes the terminal; with large scrollback buffers, even fork overhead alone adds 45ms+ per refresh. Must use cache-first architecture from day one — the status bar script reads only the cache file, never the network. Recovery cost is HIGH (full rewrite) so this must be the foundation.

3. **API key leaking via process list or git** — Passing key as curl CLI arg exposes it in `ps aux`. Storing in tmux.conf risks dotfiles repo commit. Read key from `$ANTHROPIC_ADMIN_API_KEY` env var or `~/.config/claudux/config` with chmod 600. Never pass as CLI argument. Ship a .gitignore. This is a day-one security requirement.

4. **Quota concept confusion (subscription vs API billing vs rate limits)** — "Weekly quota" in the project spec maps to Claude Pro/Max subscription limits, but there is no documented programmatic API endpoint for subscription quotas as of March 2026. The Admin API provides monthly API spend limits. Rate limit headers provide per-minute limits. Each metric needs clear labeling in the UI.

5. **Unicode progress bar width miscalculation** — tmux miscounts wide/emoji characters, causing status bar truncation or overflow. Use only single-width block characters (`\u2588-\u2591`) and provide an ASCII fallback mode. Test on at least iTerm2, GNOME Terminal, and Alacritty.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 0: Requirements Clarification
**Rationale:** The most critical open question — which quotas are being tracked — must be resolved before writing any code. PITFALLS.md explicitly calls this out as Phase 0. Building against the wrong quota concept is expensive to fix later.
**Delivers:** Definitive spec of which metrics are displayed (API billing spend, rate limits, subscription hours, or combination); definition of "org mode" vs "local mode"; clear labeling plan for UI elements.
**Addresses:** PITFALLS Pitfall 4 (quota concept confusion)
**Avoids:** Building data fetching for the wrong API, then discovering the target users don't have access to that API.

### Phase 1: Foundation Infrastructure
**Rationale:** The architecture research identifies a strict dependency order. Helpers, cache, and defaults must exist before anything else can be written or tested in isolation. The cache system in particular is the most critical architectural decision — it must be correct before API integration is layered on top.
**Delivers:** `helpers.sh`, `config/defaults.sh`, `cache.sh` with atomic writes and TTL; dependency checker (`check_deps.sh`); API key security pattern (env var / config file with chmod 600).
**Uses:** Bash 4.0+, XDG_CACHE_HOME conventions, flock for single-instance enforcement
**Avoids:** PITFALLS Pitfall 2 (blocking calls — established by design before API exists), Pitfall 3 (key security baked in from day one)

### Phase 2: API Integration
**Rationale:** With cache infrastructure in place, the API client can be written and tested against real Anthropic endpoints in isolation. This phase establishes both data sources (Admin API and local JSONL) and implements mode detection.
**Delivers:** `api.sh` with Admin API client (usage report + cost report endpoints), key type detection with clear errors, local JSONL parser as fallback (`parse_local.sh`), auto/org/local mode selection.
**Uses:** curl, jq 1.6+, Anthropic Admin API (`/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`)
**Implements:** Dual data source architecture from ARCHITECTURE.md
**Avoids:** PITFALLS Pitfall 1 (Admin key requirement), pagination gotcha (`has_more` field), API polling frequency (5-10 min TTL)

### Phase 3: Rendering and Display
**Rationale:** Rendering can be tested with hardcoded data immediately, producing visible output before full pipeline integration. Building render in isolation allows cross-terminal testing early, when Unicode issues are cheapest to fix.
**Delivers:** `render.sh` with Unicode progress bars (with ASCII fallback), tmux color formatting (`#[fg=colour]` green/yellow/red), reset time formatting, labeled segments, stale/error state indicators.
**Uses:** Unicode block chars `\u2588-\u2591`, tmux 256-color / true-color, configurable thresholds
**Implements:** Color-coded status indicators, stale data indicator, error state display from FEATURES.md
**Avoids:** PITFALLS Pitfall 5 (Unicode width bugs — test on 4+ terminals in this phase)

### Phase 4: Plugin Integration and Format Strings
**Rationale:** This is the integration phase where all components wire together into the full TPM plugin. The dispatcher is the integration point; the `.tmux` entry point is the last piece because it only does string replacement and depends on everything else being functional.
**Delivers:** `claudux.sh` dispatcher, `claudux.tmux` entry point with sed-based format string registration, all `#{claudux_*}` format strings (`weekly`, `monthly`, `model_sonnet`, `model_opus`, `reset`, `cost`, `email`, `compact`), user option reading via `tmux show-option`.
**Uses:** TPM format string registration pattern, segment-based dispatcher pattern from ARCHITECTURE.md
**Implements:** All table-stakes features from FEATURES.md; full feature set
**Avoids:** PITFALLS separate-API-call-per-segment anti-pattern; unconstrained status-right-length (set to 200+)

### Phase 5: Cross-Platform Reliability and Distribution
**Rationale:** GNU vs BSD portability issues (stat, date, curl TLS) are cheap to fix proactively but expensive when filed as bugs. TPM packaging must be validated end-to-end before public release. Multiple tmux session conflicts need explicit testing.
**Delivers:** Cross-platform compatibility (macOS BSD utils, Linux GNU utils), TPM install validation (`prefix + I`), manual git clone install path, PID-file locking for background fetcher, multiple-session conflict resolution, README with setup docs, LICENSE.
**Uses:** Platform detection in helpers.sh, `stat -c %Y` (Linux) / `stat -f %m` (macOS) dual-path, CI test matrix
**Avoids:** macOS curl/date gotchas, multiple-session background fetcher duplication, jq missing on macOS

### Phase Ordering Rationale

- Phase 0 comes first because the data source question is still open and the wrong answer propagates through all subsequent phases.
- Foundation before API because cache architecture must be correct before network calls are introduced. Retrofitting the cache pattern is PITFALLS' highest-recovery-cost failure mode.
- API before rendering because the render layer needs to know the shape of cached data (JSON structure) to write parsers correctly.
- Rendering before full plugin integration because Unicode/terminal tests are cheapest when rendering is isolated.
- Distribution last because packaging and portability validation requires a working end-to-end pipeline.
- This order mirrors the explicit "Suggested Build Order" in ARCHITECTURE.md, validated against the "Pitfall-to-Phase Mapping" in PITFALLS.md.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 0:** Subscription quota API endpoint — as of March 2026 there is no documented API for Claude Pro/Max subscription usage hours. May require OAuth token approach (undocumented, LOW confidence). Needs investigation before committing to feature set.
- **Phase 2:** Local JSONL log format — the JSONL schema at `~/.claude/projects/*/sessions/*.jsonl` is undocumented. Community tools (ccusage, Claude-Code-Usage-Monitor) have reverse-engineered it but it may change. Needs validation against current Claude Code version.
- **Phase 2:** Admin API pagination — the `has_more` / `next_page` pattern needs implementation research to ensure complete data retrieval for usage reports spanning longer periods.

Phases with standard patterns (skip research-phase):
- **Phase 1:** File caching with TTL and atomic writes is a well-documented Unix pattern; no research needed.
- **Phase 3:** tmux color formatting and Unicode block characters are thoroughly documented in tmux-battery and tmux-cpu source.
- **Phase 4:** TPM format string registration pattern is documented in the official TPM plugin creation guide with working examples.
- **Phase 5:** GNU/BSD portability for stat and date is documented across the tmux-plugins org; established solutions exist.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technology choices verified against official docs and canonical TPM plugin source. Bash + curl + jq is universally consistent across the ecosystem. |
| Features | HIGH | Competitive analysis based on real GitHub repos; table stakes derived from multiple implemented examples. Gap: subscription quota API endpoint is LOW confidence (undocumented or absent). |
| Architecture | HIGH | TPM plugin pattern verified across 6+ production plugins (tmux-battery, tmux-cpu, tmux-plugin-sysstat, Dracula, tmux-powerkit). All examples from official tmux-plugins org. |
| Pitfalls | HIGH | Pitfalls sourced from official tmux issue tracker (blocking/fork overhead, Unicode width), official Anthropic docs (Admin key requirement), and official security guidance. Not speculative. |

**Overall confidence:** HIGH

### Gaps to Address

- **Subscription quota API endpoint:** No documented programmatic API exists for Claude Pro/Max subscription usage hours as of March 2026. Before Phase 0 closes, determine if the undocumented OAuth endpoint (`/api/oauth/usage`) is viable and stable, or if the feature must be deferred until Anthropic ships official support (issue #28999). This is the highest-risk open question.
- **JSONL schema stability:** The local log format at `~/.claude/projects/*/sessions/*.jsonl` is reverse-engineered by community tools. Validate the schema against the current Claude Code version before committing to the local mode implementation in Phase 2. Add version detection in case the schema changes.
- **Admin API spend limit denominator:** The Cost Report shows current spend but not the tier limit (what the user's monthly spend cap is). The progress bar needs both numerator and denominator. Either hardcode tier limits (fragile) or find an API endpoint that exposes the configured limit. This affects Phase 3 rendering design.

## Sources

### Primary (HIGH confidence)
- [Anthropic Usage and Cost API](https://platform.claude.com/docs/en/api/usage-cost-api) — Admin API endpoints, response shapes, Auth requirements
- [Anthropic Rate Limits](https://platform.claude.com/docs/en/api/rate-limits) — Rate limit headers, tier structure
- [Anthropic Admin API Overview](https://docs.anthropic.com/en/api/administration-api) — Admin key provisioning, org requirements
- [Claude Code Analytics API](https://platform.claude.com/docs/en/api/claude-code-analytics-api) — Claude Code specific analytics endpoint
- [TPM Plugin Creation Guide](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md) — Format string registration, TPM conventions
- [tmux-battery](https://github.com/tmux-plugins/tmux-battery) — Canonical format string pattern, color coding, ASCII fallback
- [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu) — Multi-metric dispatcher pattern
- [tmux-plugin-sysstat](https://github.com/samoshkin/tmux-plugin-sysstat) — Advanced caching patterns
- [tmux Formats Wiki](https://github.com/tmux/tmux/wiki/Formats) — Native format string system
- [tmux Issue #3352](https://github.com/tmux/tmux/issues/3352) — Fork overhead with large scrollback (confirmed by maintainer)
- [tmux Issue #632](https://github.com/tmux/tmux/issues/632) / [#3865](https://github.com/tmux/tmux/issues/3865) — Unicode character width issues
- [Anthropic API Key Best Practices](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure) — Key security guidance

### Secondary (MEDIUM confidence)
- [ccusage statusline](https://ccusage.com/guide/statusline) — Competitor analysis; validates local JSONL approach
- [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) — Competitor analysis; validates JSONL schema
- [codelynx.dev statusline guide](https://codelynx.dev/posts/claude-code-usage-limits-statusline) — Competitor analysis; macOS-only but validates 5h/7d quota display patterns
- [tmux-powerkit](https://github.com/fabioluciano/tmux-powerkit) — SWR caching strategy reference
- [CI Results in tmux status line](https://blog.semanticart.com/2020/02/13/ci-results-in-your-tmux-status-line/) — Caching pattern reference

### Tertiary (LOW confidence)
- [OAuth usage endpoint](https://github.com/anthropics/claude-code/issues/13585) — Undocumented API for subscription quota data; may break without notice; needs validation before building against
- [Claude Pro/Max Weekly Rate Limits](https://hypereal.tech/a/weekly-rate-limits-claude-pro-max-guide) — Third-party source; no official API endpoint confirmed

---
*Research completed: 2026-03-10*
*Ready for roadmap: yes*
