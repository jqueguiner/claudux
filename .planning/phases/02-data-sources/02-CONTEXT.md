# Phase 2: Data Sources - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Fetch and normalize quota data from both the Anthropic Admin API (organization users) and local Claude Code JSONL session logs (subscription users). Write normalized data to the shared cache using Phase 1's cache system. Auto-detect which mode to use based on available credentials. No rendering, no format strings — just data fetching and normalization.

</domain>

<decisions>
## Implementation Decisions

### Admin API client (org mode)
- New script: `scripts/api_fetch.sh` — fetches from Anthropic Admin API endpoints
- Uses `load_api_key` from credentials.sh and validates it's an admin key via `get_key_type`
- Endpoints to call:
  - `/v1/organizations/usage_report/messages` — token usage per model (Sonnet, Opus) for current billing period
  - `/v1/organizations/cost_report` — spend in USD for current billing period
  - `/v1/organizations/members` — to retrieve account email (admin only)
- Pass API key via `x-api-key` header (never as URL parameter)
- Read response with `jq` and normalize to cache schema
- Handle pagination: check `has_more` field, follow `next_page` if present
- Error handling: capture HTTP status code via `curl -w '%{http_code}'`, map to clear messages
  - 401/403 → "Invalid or insufficient API key"
  - 429 → "Rate limited — increase refresh interval"
  - 5xx → "Anthropic API unavailable"

### Local JSONL log parser (local mode)
- New script: `scripts/local_parse.sh` — parses Claude Code session logs
- Log location: `~/.claude/projects/*/sessions/*.jsonl`
- Extract from each JSONL entry: model used, input tokens, output tokens, timestamp
- Aggregate by time window:
  - Weekly: last 7 days rolling
  - Monthly: last 30 days rolling (or calendar month if determinable)
  - Per-model: group by model name (sonnet, opus)
- Calculate usage percentages against known plan limits:
  - Read plan type from `@claudux_plan` tmux option (default: "max_5x")
  - Hardcoded limit table: { free: {...}, pro: {...}, max_5x: {...}, max_20x: {...} }
  - Document that limits are approximate and may change
- No API key needed — reads local files only

### Normalized cache schema
- Both data sources write the same JSON structure to cache.json:
```json
{
  "mode": "org|local",
  "fetched_at": 1710000000,
  "account": {
    "email": "user@example.com"
  },
  "weekly": {
    "used": 45.2,
    "limit": 100,
    "unit": "percent|usd|tokens",
    "reset_at": 1710100000
  },
  "monthly": {
    "used": 120.50,
    "limit": 500,
    "unit": "percent|usd|tokens",
    "reset_at": 1710500000
  },
  "models": {
    "sonnet": {
      "used": 30.1,
      "limit": 100,
      "unit": "percent|tokens",
      "reset_at": 1710100000
    },
    "opus": {
      "used": 12.5,
      "limit": 100,
      "unit": "percent|tokens",
      "reset_at": 1710100000
    }
  },
  "error": null
}
```
- `error` field: null when data is valid, or `{"code": "auth_failed", "message": "..."}` on failure
- Renderer (Phase 3) only reads this schema — source-agnostic

### Mode auto-detection
- New script: `scripts/detect_mode.sh` — determines data source mode
- Detection logic:
  1. Try `load_api_key` from credentials.sh
  2. If key found and `get_key_type` returns "admin" → org mode
  3. If no key found, check if `~/.claude/` directory exists with JSONL logs → local mode
  4. If neither available → write error to cache: `{"error": {"code": "no_source", "message": "..."}}`
- Log detected mode to stderr (for debugging): `"claudux: using org mode"` or `"claudux: using local mode"`
- Mode can be forced via `@claudux_mode` tmux option ("org", "local", "auto")

### Data fetch orchestration
- New script: `scripts/fetch.sh` — main entry point for data refresh
- Flow:
  1. Acquire lock (from cache.sh)
  2. Check if cache is stale (from cache.sh)
  3. If fresh → exit early (another process already refreshed)
  4. Detect mode (from detect_mode.sh)
  5. Call appropriate fetcher (api_fetch.sh or local_parse.sh)
  6. Write normalized JSON to cache (from cache.sh)
  7. Release lock
- This is what the status bar scripts will call (Phase 5) to ensure fresh data

### Claude's Discretion
- Exact jq filter expressions for API response parsing
- JSONL line-by-line parsing approach (while read loop vs jq slurp)
- How to handle incomplete/corrupt JSONL entries
- Specific curl flags for timeouts and retries
- Plan limit values (these will change — just use best-known current values)

</decisions>

<specifics>
## Specific Ideas

- Research found the Admin API requires `sk-ant-admin` prefix — already handled by Phase 1's credentials.sh
- Research warned JSONL schema is undocumented and may change — add version detection comment in parser
- User wants "account email" displayed — org mode gets this from members endpoint, local mode can try parsing `~/.claude/settings.json` or config
- Keep scripts minimal and single-purpose — user emphasized pragmatism

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/cache.sh`: cache_write(), cache_read(), is_cache_stale(), acquire_lock(), release_lock() — full cache lifecycle
- `scripts/credentials.sh`: load_api_key(), get_key_type() — credential loading and admin key detection
- `scripts/helpers.sh`: get_platform(), get_cache_dir(), get_config_dir(), get_tmux_option() — cross-platform utilities
- `config/defaults.sh`: CLAUDUX_DEFAULT_REFRESH_INTERVAL (300s) — TTL default

### Established Patterns
- Source helpers.sh at top of every script: `source "$CURRENT_DIR/helpers.sh"`
- Use `get_cache_dir()` for cache paths, `get_config_dir()` for config paths
- Atomic cache writes via cache_write() — never write to cache.json directly
- Lock before writing: acquire_lock() / release_lock() bracket

### Integration Points
- `fetch.sh` will be called by the dispatcher (Phase 5) when cache is stale
- `cache_write()` is the single write path — both api_fetch.sh and local_parse.sh use it
- `load_api_key()` + `get_key_type()` drive mode detection
- Cache schema defined here becomes the contract for Phase 3 (rendering)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-data-sources*
*Context gathered: 2026-03-10*
