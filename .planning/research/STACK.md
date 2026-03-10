# Technology Stack

**Project:** Claudux (tmux status bar plugin for Claude API usage monitoring)
**Researched:** 2026-03-10

## Recommended Stack

### Core Runtime

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Bash | 4.0+ (POSIX-compatible) | Plugin runtime, all script logic | TPM convention -- every major tmux plugin (tmux-battery, tmux-powerline, tmux-powerkit) is pure Bash. No interpreter dependency beyond what ships with every Linux/macOS system. Using Python or Node would be an anti-pattern in this ecosystem. | HIGH |
| tmux | 3.0+ (current stable: 3.5a/3.6a) | Host environment | PROJECT.md specifies tmux 3.0+ compatibility. Current stable is 3.5a on most distros, 3.6a on bleeding edge. Format string interpolation (`#(...)` shell command embedding) has been stable since 2.1. | HIGH |

### Plugin Framework

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| TPM (Tmux Plugin Manager) | latest (active, maintained) | Plugin discovery, installation, loading | De facto standard for tmux plugin distribution. TPM discovers plugins by executing `*.tmux` files in the plugin root. Users install via `set -g @plugin 'username/repo'` in `.tmux.conf`. No alternative has meaningful adoption. | HIGH |

### Data Fetching

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| curl | 7.x / 8.x (system-provided) | HTTP requests to Anthropic Admin API | Universally available on Linux/macOS. Supports custom headers (`x-api-key`, `anthropic-version`). Lightweight enough for status bar refresh cycles. Alternatives like `wget` lack header control. `httpie` is not universally installed. | HIGH |

### JSON Processing

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| jq | 1.6+ (latest: 1.8.1) | Parse API JSON responses, extract token counts and costs | The standard CLI JSON processor. Zero runtime dependencies (single binary, written in C). Handles nested JSON extraction that would require fragile `grep`/`sed` hacks otherwise. Widely installed; easy to check and prompt install. | HIGH |

### Data Sources

| Source | Type | Auth | Purpose | Confidence |
|--------|------|------|---------|------------|
| Anthropic Admin API (`/v1/organizations/usage_report/messages`) | REST API | Admin API key (`sk-ant-admin...`) | Organization-level token usage by model, workspace, time bucket. Primary data source for API quota tracking. | HIGH |
| Anthropic Admin API (`/v1/organizations/cost_report`) | REST API | Admin API key (`sk-ant-admin...`) | Cost breakdowns in USD by service. Daily granularity only. | HIGH |
| Local Claude Code JSONL logs (`~/.claude/projects/*/sessions/*.jsonl`) | Local files | None (filesystem) | Individual developer session-level token tracking. Fallback for users without Admin API access. | MEDIUM |
| Anthropic rate limit response headers | HTTP headers | Standard API key | Per-request remaining quota, limits, reset times (e.g., `anthropic-ratelimit-tokens-remaining`). Available on any API response but requires making a real API call to obtain. | HIGH |

### Caching Layer

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| File-based cache (tmpfs/XDG_CACHE_HOME) | N/A (custom implementation) | Cache API responses between tmux status refreshes | tmux status bar refreshes every 15s by default (configurable via `status-interval`). The Anthropic Usage API supports polling once per minute. Caching responses to a local file with a TTL (e.g., 5 minutes for usage data) prevents hammering the API and keeps the status bar responsive. This is the pattern used by tmux-powerkit (SWR caching) and the CI-status-in-tmux pattern. | HIGH |

### Configuration

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| tmux user options (`@claudux-*`) | N/A (tmux built-in) | User-configurable settings | TMux plugins conventionally use `set -g @plugin-option value` in `.tmux.conf`. The plugin reads these via `tmux show-option -gqv @claudux-option`. This is the standard TPM configuration pattern (used by tmux-battery, tmux-continuum, dracula/tmux). No config files needed. | HIGH |
| `.claudux.conf` fallback | N/A | API key storage, advanced config | For sensitive data like the Admin API key, reading from `$ANTHROPIC_ADMIN_API_KEY` env var first, then falling back to `~/.config/claudux/config` (XDG-compliant). Never store keys in `.tmux.conf`. | MEDIUM |

### Display / Rendering

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Unicode block characters | N/A | Progress bar rendering | Use `\u2588` (full block), `\u2593` (dark shade), `\u2592` (medium shade), `\u2591` (light shade), or simpler `[####----]` ASCII fallback. PROJECT.md specifies progress bars for quotas. Most modern terminals handle Unicode blocks fine. | HIGH |
| tmux format strings (`#{...}`) | N/A | Custom status bar interpolation | Plugin registers format strings like `#{claudux_usage}`, `#{claudux_cost}`, `#{claudux_reset}`. Users place these in `status-right` or `status-left`. tmux expands `#(script.sh)` to script output on each refresh. | HIGH |
| tmux styling (`#[fg=...,bg=...]`) | N/A | Color-coded progress bars | tmux supports 256 colors and true color (tmux 3.2+). Use color gradients: green (< 50%), yellow (50-80%), red (> 80%) for quota usage bars. | HIGH |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Language | Bash | Python | Python is not universally available at consistent versions, adds a runtime dependency, and violates tmux plugin conventions. Every canonical TPM plugin is Bash. |
| Language | Bash | Go (compiled binary) | Overkill for simple API fetch + format. Adds compilation step, binary distribution complexity. Only justified if performance becomes a bottleneck (unlikely -- we cache responses). |
| Language | Bash | Node.js | Heavy runtime dependency. Not installed on many servers. Completely wrong ecosystem for tmux plugins. |
| JSON parsing | jq | Python one-liner | Adds Python dependency. `jq` is purpose-built, faster, and more commonly available in server/dev environments. |
| JSON parsing | jq | grep/sed/awk | Fragile, breaks on nested JSON, formatting changes. JSON needs a real parser. |
| JSON parsing | jq | gron | Less widely available, less well-known. `jq` is the standard. |
| Plugin manager | TPM | Manual install | TPM is the standard. Users expect `set -g @plugin` workflow. Manual install is a fallback, not primary distribution. |
| Caching | File-based (tmpfs) | Redis/SQLite | Massive overkill. We need a single cached JSON blob with a TTL. A temp file with `stat` for age checking is sufficient. |
| Data source | Admin API | Screen-scraping Console | Brittle, unauthorized, will break. The Admin API is the official programmatic interface. |
| Data source | Admin API + local logs | Rate limit headers only | Headers only show per-minute rate limits, not cumulative spend or monthly quotas. Useful as supplementary data but insufficient alone. |

## Critical Design Decisions

### 1. Admin API Key Requirement

The Anthropic Usage & Cost API requires an **Admin API key** (`sk-ant-admin...`), not a standard API key. This is only available to organization admins, not individual account holders.

**Implications:**
- Individual developers without an organization cannot use the Admin API
- The plugin MUST support a fallback: parsing local Claude Code JSONL logs for individual users
- Two operational modes: "org mode" (Admin API) and "local mode" (JSONL parsing)
- Document this clearly -- users will need to provision an Admin key from Console > Settings > Admin Keys

### 2. Dual Data Source Strategy

| Mode | Data Source | Users | Capabilities |
|------|------------|-------|-------------|
| **Org Mode** | Admin API (`usage_report` + `cost_report`) | Organization admins | Full token usage by model, cost in USD, workspace breakdown, time-bucketed history |
| **Local Mode** | `~/.claude/projects/*/sessions/*.jsonl` | Individual developers | Session token counts, per-model usage, cost estimation (calculated from published pricing) |

Both modes output to the same tmux format strings. The rendering layer is agnostic to the data source.

### 3. Cache TTL Strategy

| Data Type | Recommended TTL | Rationale |
|-----------|----------------|-----------|
| Usage report (Admin API) | 5 minutes | API supports 1/min polling. 5 min reduces load while keeping data fresh enough for a status bar. |
| Cost report (Admin API) | 15 minutes | Daily granularity only (`1d` buckets), so frequent polling is wasteful. |
| Local JSONL parsing | 2 minutes | Files change with each Claude Code session. Fast parsing (local I/O) allows shorter TTL. |
| Rate limit headers | 30 seconds | Changes with every API call. Only useful if we piggyback on other requests. |

### 4. tmux Integration Pattern

Follow the tmux-battery pattern exactly:
1. Main entry: `claudux.tmux` (TPM loads this)
2. Scripts directory: `scripts/` with individual scripts per format string
3. Format strings: `#{claudux_weekly}`, `#{claudux_monthly}`, `#{claudux_model}`, `#{claudux_cost}`, `#{claudux_reset}`, `#{claudux_email}`
4. User configuration via `@claudux-*` tmux options
5. Each `#(...)` call reads from cache file, never blocks on network

## Dependency Checklist

### Required (hard dependencies)

| Dependency | Check Command | Install Guidance |
|------------|---------------|-----------------|
| tmux 3.0+ | `tmux -V` | System package manager |
| bash 4.0+ | `bash --version` | Ships with OS (macOS may need `brew install bash` for 5.x) |
| curl | `curl --version` | `apt install curl` / `brew install curl` |
| jq 1.6+ | `jq --version` | `apt install jq` / `brew install jq` |

### Optional (enhance functionality)

| Dependency | Purpose | Fallback |
|------------|---------|----------|
| Anthropic Admin API key | Org-level usage data | Local JSONL parsing mode |
| Nerd Fonts / Unicode support | Pretty progress bars | ASCII fallback `[####----]` |

## Installation

```bash
# Via TPM (recommended)
# Add to .tmux.conf:
set -g @plugin 'username/claudux'

# Then press prefix + I to install

# Manual installation:
git clone https://github.com/username/claudux ~/.tmux/plugins/claudux

# Verify dependencies:
bash ~/.tmux/plugins/claudux/scripts/check_deps.sh
```

### Configuration (in .tmux.conf)

```bash
# Required: API key (or set ANTHROPIC_ADMIN_API_KEY env var)
set -g @claudux-api-key "sk-ant-admin-..."

# Optional: customize what to display
set -g @claudux-show-weekly "on"       # default: on
set -g @claudux-show-monthly "on"      # default: on
set -g @claudux-show-model "on"        # default: on (Sonnet usage)
set -g @claudux-show-cost "on"         # default: off
set -g @claudux-show-reset "on"        # default: on
set -g @claudux-show-email "off"       # default: off
set -g @claudux-refresh-interval "300" # seconds, default: 300 (5 min)
set -g @claudux-mode "auto"            # auto|org|local

# Add to status bar:
set -g status-right '#{claudux_weekly} #{claudux_monthly} #{claudux_reset}'
```

## File Structure

```
claudux/
  claudux.tmux              # TPM entry point
  scripts/
    claudux_weekly.sh        # Outputs weekly usage progress bar
    claudux_monthly.sh       # Outputs monthly usage progress bar
    claudux_model.sh         # Outputs per-model (Sonnet) usage bar
    claudux_cost.sh          # Outputs cost in USD
    claudux_reset.sh         # Outputs next reset date/time
    claudux_email.sh         # Outputs account email
    helpers.sh               # Shared functions (caching, formatting, color)
    fetch_usage.sh           # Admin API data fetcher (writes to cache)
    parse_local.sh           # Local JSONL parser (writes to cache)
    check_deps.sh            # Dependency checker
  config/
    defaults.sh              # Default option values
  LICENSE
  README.md
```

## API Reference (Key Endpoints)

### Usage Report

```bash
GET https://api.anthropic.com/v1/organizations/usage_report/messages
Headers:
  anthropic-version: 2023-06-01
  x-api-key: $ADMIN_API_KEY
Query params:
  starting_at: ISO 8601 timestamp
  ending_at: ISO 8601 timestamp
  bucket_width: 1m | 1h | 1d
  group_by[]: model | workspace_id | api_key_id | service_tier
  models[]: claude-sonnet-4-6 | claude-opus-4-6 | etc.
```

### Cost Report

```bash
GET https://api.anthropic.com/v1/organizations/cost_report
Headers:
  anthropic-version: 2023-06-01
  x-api-key: $ADMIN_API_KEY
Query params:
  starting_at: ISO 8601 timestamp
  ending_at: ISO 8601 timestamp
  bucket_width: 1d  # daily only
  group_by[]: workspace_id | description
```

### Rate Limit Headers (from any Messages API response)

```
anthropic-ratelimit-requests-limit
anthropic-ratelimit-requests-remaining
anthropic-ratelimit-requests-reset
anthropic-ratelimit-input-tokens-limit
anthropic-ratelimit-input-tokens-remaining
anthropic-ratelimit-input-tokens-reset
anthropic-ratelimit-output-tokens-limit
anthropic-ratelimit-output-tokens-remaining
anthropic-ratelimit-output-tokens-reset
```

## Sources

- [TPM - How to create a plugin](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md) - HIGH confidence (official docs)
- [Anthropic Usage and Cost API](https://platform.claude.com/docs/en/api/usage-cost-api) - HIGH confidence (official docs, fetched 2026-03-10)
- [Anthropic Rate Limits](https://platform.claude.com/docs/en/api/rate-limits) - HIGH confidence (official docs, fetched 2026-03-10)
- [tmux-battery plugin](https://github.com/tmux-plugins/tmux-battery) - HIGH confidence (canonical TPM plugin example)
- [tmux-powerline](https://github.com/erikw/tmux-powerline) - HIGH confidence (popular bash-only status bar plugin)
- [tmux Formats wiki](https://github.com/tmux/tmux/wiki/Formats) - HIGH confidence (official tmux docs)
- [ccusage - Claude Code usage analyzer](https://github.com/ryoppippi/ccusage) - MEDIUM confidence (community tool, validates JSONL structure)
- [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) - MEDIUM confidence (community tool, validates local usage patterns)
- [jq official site](https://jqlang.org/) - HIGH confidence (official project site)
- [tmux releases](https://github.com/tmux/tmux/releases) - HIGH confidence (official releases, current: 3.6a)
- [CI Results in tmux status line](https://blog.semanticart.com/2020/02/13/ci-results-in-your-tmux-status-line/) - MEDIUM confidence (caching pattern reference)
- [tmux-powerkit](https://github.com/fabioluciano/tmux-powerkit) - MEDIUM confidence (SWR caching pattern reference)
- [Anthropic Admin API overview](https://docs.anthropic.com/en/api/administration-api) - HIGH confidence (official docs)
