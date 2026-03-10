# Feature Landscape

**Domain:** tmux status bar plugin for Claude API usage monitoring
**Researched:** 2026-03-10

## Context: Two Distinct User Segments

This plugin serves two overlapping but distinct audiences with different data sources:

1. **Claude Code subscription users (Pro/Max)** -- Have 5-hour rolling and 7-day weekly quotas, subscription-tier limits. Data available via undocumented OAuth endpoint (`/api/oauth/usage`) or the `/usage` REPL command in Claude Code. The Admin API is NOT available for individual accounts.

2. **API (pay-as-you-go) organization users** -- Have spend limits and rate limits (RPM/ITPM/OTPM) per tier. Data available via the Admin API (`/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`), which requires an Admin API key (`sk-ant-admin...`) and an organization setup.

The PROJECT.md references "consumption quotas (weekly, monthly)" and "the account email associated with the API key," which aligns with the **organization/API user** segment. However, the strongest pain point in the ecosystem is among **Claude Code subscription users** who have opaque, hard-to-track quotas. The plugin should target both, but lead with the subscription use case because that is where 10+ duplicate GitHub issues exist requesting this exact functionality.

---

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Quota usage as progress bars** | Core value prop. Every competing tool (claude-code-limit-tracker, Claude-Code-Usage-Monitor, ccusage statusline) shows percentage-based usage. Unicode block characters (U+2588 through U+2591) render reliably in modern terminals. | Med | Must handle both percentage-of-limit (subscription) and tokens-consumed (API) representations. Use partial block chars for smooth bars. |
| **Quota reset countdown** | Users need to know WHEN capacity returns, not just current usage. The codelynx.dev statusline and claude-code-limit-tracker both show reset times. | Low | Display as "resets in Xh Ym" relative format, not absolute timestamps. Subscription users have 5-hour rolling + 7-day windows; API users have token bucket continuous replenishment (no fixed reset). |
| **Model-specific usage breakdown** | Claude Code enforces separate limits for Opus vs Sonnet. Users hit Opus limits first and need to know per-model status. The claude-code-limit-tracker tracks Sonnet 4 and Opus 4 separately with distinct weekly quotas. | Med | At minimum: Opus and Sonnet as separate bars. API users get per-model data from the usage report endpoint grouped by model. |
| **Auto-refresh with caching** | tmux status bars refresh on `status-interval` (default 15s). API calls must be cached to avoid rate limiting and latency. Every tmux plugin in the ecosystem (tmux-battery, tmux-cpu) caches results. The Anthropic Usage API recommends polling no more than once per minute. | Med | Cache responses to file (e.g., `/tmp/claudux-cache.json`). Refresh cache on configurable interval (default: 5 min). Serve stale cache between refreshes. Status bar script reads cache file, never calls API directly. |
| **TPM compatibility** | De facto standard for tmux plugin distribution. Users expect `set -g @plugin 'user/claudux'` and `prefix + I`. Every major tmux plugin (tmux-battery, tmux-cpu, tmux-sensible) uses TPM. | Low | Follow TPM conventions: `claudux.tmux` entry point, `scripts/` directory, format string interpolation via `#()` shell command syntax. |
| **tmux format string interpolation** | Standard pattern for tmux plugins. Users expect `#{claudux_quota_weekly}` style format strings they can place anywhere in status-left or status-right. tmux-battery exposes 12 such format strings. | Med | Provide format strings like `#{claudux_bar}`, `#{claudux_weekly}`, `#{claudux_reset}`, `#{claudux_model_opus}`, `#{claudux_model_sonnet}`. Each maps to a shell script in `scripts/`. |
| **Color-coded status indicators** | Visual urgency signaling. tmux-battery uses color tiers based on charge level. ccusage uses green/yellow/red for burn rate. Users expect at-a-glance severity. | Low | Green (< 50% used), yellow (50-80%), red (> 80%). Use tmux `#[fg=colour]` syntax. Configurable thresholds via `@claudux_warning_threshold` and `@claudux_critical_threshold`. |
| **Configurable display** | Every tmux plugin allows customization via `set -g @plugin_option value`. Users expect to toggle which stats appear, set colors, and control format. | Low | Support `@claudux_show_weekly`, `@claudux_show_model`, `@claudux_show_reset`, `@claudux_bar_length`, `@claudux_colors` tmux options. |
| **Cross-platform (Linux + macOS)** | PROJECT.md constraint: "tmux 3.0+ on Linux and macOS." All major tmux plugins support both. | Low | Shell scripts must work with both GNU and BSD utils. Credential retrieval differs: macOS uses Keychain, Linux uses file-based credential stores. |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Dual data source support (subscription + API)** | No existing tool handles both Claude Code subscription quotas AND organization API usage in one plugin. claude-code-limit-tracker is subscription-only. The Admin API tools are organization-only. Claudux could be the single pane of glass. | High | Detect auth type (OAuth token vs Admin API key) and adapt display. Different data shapes require different parsing. This is the key differentiator. |
| **Claude Code statusLine hook integration** | Claude Code has a statusLine hook system (Beta) for feeding session data to external scripts. If/when Anthropic exposes quota data in statusLine JSON (issue #28999, 10+ duplicate requests), Claudux could consume it directly -- zero additional API calls. | Med | Monitor the statusLine payload. Today it lacks quota data, but building the hook integration now means we are ready when Anthropic ships it. Fall back to direct API polling until then. |
| **Compact single-segment mode** | A combined, information-dense single status segment: `W:45% O:12% S:8% [2h]`. Most competing tools produce verbose multi-line or multi-segment output. Power users want density. | Low | Single format string `#{claudux_compact}` that packs all metrics into one tight segment. Contrast with the full multi-segment format strings. |
| **Background daemon for cache refresh** | Instead of fetching on each status-interval tick, run a lightweight background process that refreshes the cache independently. Status bar reads always hit cache (instant). Eliminates latency spikes in status bar rendering. | Med | Use a simple shell loop or a tmux `run-shell -b` background process. Write to cache file atomically. Kill on tmux server exit via `session-closed` hook. |
| **Subscription plan auto-detection** | Automatically detect whether user is on Free, Pro, Max 5x, or Max 20x and adjust limit denominators accordingly. The claude-code-limit-tracker requires manual `--plan` flag. | Med | Parse plan info from OAuth usage endpoint response or allow config override via `@claudux_plan`. Less friction than competitors that require manual plan specification. |
| **Spend tracking for API users** | Show cumulative spend for current billing period in USD. The Admin API Cost endpoint provides this. No tmux plugin currently surfaces API spend. | Med | Format as `$X.XX` or `$X.XX/$Y.00` (spent/limit). Only available for organization API users, not subscription users. |
| **Stale data indicator** | Show a visual marker (e.g., dimmed color or `?` suffix) when cached data is older than expected refresh interval. Users know the data might be outdated. | Low | Compare cache file mtime to current time. If stale beyond 2x refresh interval, add indicator. Simple but builds trust. |
| **Error state display** | Show clear indicator when API auth fails, rate limit hit, or network error occurs instead of showing nothing or stale data. | Low | Display `[!]` or `[ERR]` with tmux `#[fg=red]`. Log detailed error to file for debugging. Critical for onboarding experience. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Historical usage graphs/charts** | PROJECT.md explicitly out of scope. Terminal status bars are 1-2 lines tall -- no room for graphs. The Claude Console already has excellent usage charts. Adding charting means adding a TUI, which changes the product entirely. | Show current-period stats only. Link users to Console for history. |
| **Billing management or payment actions** | PROJECT.md explicitly out of scope. Write-only operations on billing are dangerous in a status bar script. Security liability. | Read-only display only. Never write to API. |
| **Support for non-Claude AI providers** | PROJECT.md explicitly out of scope. Each provider has different APIs, auth, and quota structures. Scope creep would kill the project. | Stay Claude-focused. Name and brand reflect this (Claudux). |
| **Web dashboard or GUI** | PROJECT.md explicitly out of scope. The value proposition is terminal-native, zero-context-switch monitoring. A web UI competes with the Claude Console itself. | Terminal only. tmux status bar is the UI. |
| **Session management or Claude Code orchestration** | Tools like claude-tmux and Codeman already do this well. Claudux is a monitoring tool, not a session manager. Mixing concerns dilutes both. | Stay focused on usage display. Complement session managers, don't replace them. |
| **AI-powered usage predictions/ML** | Claude-Code-Usage-Monitor does ML-based predictions. Adds Python/numpy dependency, complexity, and questionable accuracy given Anthropic's opaque and changing limit structures. | Show raw data and simple projections (burn rate extrapolation at most). Let users interpret. |
| **Desktop notifications or alerts** | Requires platform-specific notification systems (notify-send, osascript). Adds complexity for minimal value -- users see the status bar already. | Color coding provides urgency signaling. Users see red bar = slow down. |
| **Token-level request logging** | Requires intercepting API calls or parsing session files. Privacy concern. Heavy I/O. ccusage already does this well. | Consume aggregate data from APIs only. |

## Feature Dependencies

```
TPM compatibility → tmux format string interpolation (format strings need TPM loading)
tmux format strings → Quota usage as progress bars (bars are rendered via format strings)
tmux format strings → Quota reset countdown (reset is a format string)
tmux format strings → Model-specific usage breakdown (each model is a format string)
tmux format strings → Color-coded status indicators (colors wrap format strings)

Auto-refresh with caching → Background daemon (daemon is an enhancement to basic caching)
Auto-refresh with caching → Stale data indicator (needs cache timestamps)
Auto-refresh with caching → Error state display (errors detected during refresh)

Dual data source support → Subscription plan auto-detection (only for subscription source)
Dual data source support → Spend tracking (only for API source)

Claude Code statusLine hook → Dual data source support (statusLine is one data source)
```

Dependency chain for MVP:
```
1. Auto-refresh with caching (foundation -- all display depends on cached data)
2. TPM compatibility + tmux format strings (plugin infrastructure)
3. Quota usage bars + reset countdown + color coding (core display)
4. Model-specific breakdown (extends core display)
5. Configurable display (user customization layer)
```

## MVP Recommendation

Prioritize:
1. **Auto-refresh with caching** -- Foundation layer. Without this, status bar lags or hammers the API.
2. **TPM compatibility + format string interpolation** -- Distribution and integration mechanism. Users install via TPM, configure via format strings.
3. **Quota usage progress bars with color coding** -- Core visual value. The "screenshot moment" that sells the plugin.
4. **Quota reset countdown** -- Second most-requested data point after usage percentage.
5. **One data source first: subscription (OAuth)** -- Larger pain point, more users asking for it. Claude Code subscription users have 10+ open GitHub issues requesting exactly this.

Defer:
- **API/organization data source**: Phase 2. Requires Admin API key, different auth flow, different data shape. Ship for subscription users first.
- **Model-specific breakdown**: Phase 2. Valuable but not blocking. The basic weekly/5-hour bars are sufficient for MVP.
- **Background daemon**: Phase 2. Basic caching (refresh in status-interval callback with file lock) is sufficient for MVP.
- **Claude Code statusLine hook**: Phase 2-3. Depends on Anthropic shipping quota data in statusLine JSON (issue #28999). Build the consumer when the data is available.
- **Dual data source support**: Phase 2-3. Significant complexity. Get one source right first.
- **Compact single-segment mode**: Phase 2. Easy to add once format strings exist.

## Competitive Landscape Summary

| Tool | What It Does | Limitation Claudux Addresses |
|------|-------------|------------------------------|
| [claude-code-limit-tracker](https://github.com/TylerGallenbeck/claude-code-limit-tracker) | Python status line showing per-model quota usage from local session files | Requires manual `--plan` flag, Python+numpy dependency, not a tmux plugin (no TPM), parses local files instead of API |
| [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | Rich TUI with ML predictions, burn rate, multi-view | Heavy (Python, Rich, Pydantic, optional Sentry), full TUI not a status bar segment, overkill for glanceable monitoring |
| [ccusage statusline](https://ccusage.com/guide/statusline) | Single-line cost/burn rate display | Focused on cost/burn rate, not quota percentages. No TPM plugin. |
| [codelynx.dev approach](https://codelynx.dev/posts/claude-code-usage-limits-statusline) | TypeScript/Bun script showing 5h/7d utilization | macOS-only (Keychain dependency), not packaged as tmux plugin, manual install |
| [Claude Usage Tracker (Chrome)](https://chromewebstore.google.com/detail/claude-usage-tracker/knemcdpkggnbhpoaaagmjiigenifejfo) | Browser extension for claude.ai | Browser-only, not terminal-integrated |
| [claude-quota-tracker (VS Code)](https://github.com/jonis100/claude-quota-tracker) | VS Code status bar integration | IDE-specific, not available for terminal-only workflows |

**Claudux gap:** No existing tool is a proper tmux plugin (TPM-installable) that shows Claude usage quotas via format strings. Every competitor is either a standalone script, a full TUI, or platform-specific. Claudux fills the "tmux-battery but for Claude quotas" niche.

## Sources

- [Anthropic Usage and Cost API](https://platform.claude.com/docs/en/api/usage-cost-api) -- Official documentation (HIGH confidence)
- [Anthropic Rate Limits](https://platform.claude.com/docs/en/api/rate-limits) -- Official documentation (HIGH confidence)
- [Claude Code Analytics API](https://platform.claude.com/docs/en/api/claude-code-analytics-api) -- Official documentation (HIGH confidence)
- [Issue #28999: Expose quota data in statusLine JSON](https://github.com/anthropics/claude-code/issues/28999) -- Community feature request (HIGH confidence)
- [Issue #13585: Quota Information Access to CLI](https://github.com/anthropics/claude-code/issues/13585) -- Community feature request (HIGH confidence)
- [claude-code-limit-tracker](https://github.com/TylerGallenbeck/claude-code-limit-tracker) -- Competitor analysis (HIGH confidence)
- [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) -- Competitor analysis (HIGH confidence)
- [codelynx.dev statusline guide](https://codelynx.dev/posts/claude-code-usage-limits-statusline) -- Competitor analysis (MEDIUM confidence)
- [ccusage statusline](https://ccusage.com/guide/statusline) -- Competitor analysis (MEDIUM confidence)
- [tmux-battery plugin](https://github.com/tmux-plugins/tmux-battery) -- Architecture reference for TPM plugin patterns (HIGH confidence)
- [tmux-cpu plugin](https://github.com/tmux-plugins/tmux-cpu) -- Architecture reference (HIGH confidence)
- [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm) -- Plugin distribution standard (HIGH confidence)
- [Using Claude Code with Pro/Max](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan) -- Official documentation (HIGH confidence)
- [Claude Code usage limits (Portkey)](https://portkey.ai/blog/claude-code-limits/) -- Third-party analysis (MEDIUM confidence)
- [OAuth usage endpoint discovery](https://github.com/anthropics/claude-code/issues/13585) -- Community workaround, undocumented API (LOW confidence -- may break)
