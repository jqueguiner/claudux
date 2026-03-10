# Phase 2: Data Sources - Research

**Researched:** 2026-03-10
**Domain:** Anthropic Admin API, Claude Code JSONL log parsing, Bash scripting
**Confidence:** HIGH

## Summary

Phase 2 builds two data fetchers (Admin API client and local JSONL parser) plus a mode auto-detector, all writing to the normalized cache schema defined in CONTEXT.md. The Admin API is well-documented with stable endpoints for usage reports (`/v1/organizations/usage_report/messages`) and cost reports (`/v1/organizations/cost_report`). The JSONL session log format is undocumented but stable -- each assistant message includes `message.model`, `message.usage.input_tokens`, `message.usage.output_tokens`, and a top-level `timestamp`. Mode detection is straightforward: check for admin key via existing `load_api_key()` + `get_key_type()`.

**Primary recommendation:** Use the Admin API usage endpoint with `bucket_width=1d` and `group_by[]=model` for org mode. For local mode, parse assistant-type entries from JSONL files, summing tokens by model. Both paths write to the same normalized cache.json via `cache_write()`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Admin API client: `scripts/api_fetch.sh` -- fetches from Anthropic Admin API endpoints
- Uses `load_api_key` from credentials.sh and validates via `get_key_type`
- Endpoints: `/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`, `/v1/organizations/users` (for email)
- Pass API key via `x-api-key` header (never as URL parameter)
- Read response with `jq` and normalize to cache schema
- Handle pagination: check `has_more` field, follow `next_page` if present
- Error handling: capture HTTP status code via `curl -w '%{http_code}'`, map to clear messages (401/403, 429, 5xx)
- Local JSONL parser: `scripts/local_parse.sh` -- parses Claude Code session logs at `~/.claude/projects/*/sessions/*.jsonl`
- Extract from each JSONL entry: model used, input tokens, output tokens, timestamp
- Aggregate by time window (weekly: 7 days rolling, monthly: 30 days rolling)
- Per-model grouping by model name (sonnet, opus)
- Calculate usage percentages against known plan limits from `@claudux_plan` tmux option
- Hardcoded limit table: { free, pro, max_5x, max_20x }
- Mode auto-detection: `scripts/detect_mode.sh`
- Detection logic: try `load_api_key`, check `get_key_type` for "admin", else check for `~/.claude/` JSONL logs
- Mode can be forced via `@claudux_mode` tmux option ("org", "local", "auto")
- Data fetch orchestration: `scripts/fetch.sh` -- main entry point
- Normalized cache schema: both sources write same JSON structure to cache.json

### Claude's Discretion
- Exact jq filter expressions for API response parsing
- JSONL line-by-line parsing approach (while read loop vs jq slurp)
- How to handle incomplete/corrupt JSONL entries
- Specific curl flags for timeouts and retries
- Plan limit values (approximate, will change)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DATA-01 | Plugin fetches usage data from Anthropic Admin API for organization users | Admin API usage endpoint fully documented; curl + jq approach verified with official examples |
| DATA-02 | Plugin parses local Claude Code JSONL session logs for subscription users | JSONL format verified from live session files; assistant entries contain model + usage.input_tokens + usage.output_tokens |
| DATA-03 | Plugin auto-detects data source mode based on available credentials | `load_api_key()` + `get_key_type()` from Phase 1 provide detection; `@claudux_mode` override via `get_tmux_option()` |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| curl | 7.x+ | HTTP client for Admin API | Universal on Linux/macOS, built-in redirect/error handling |
| jq | 1.6+ | JSON parsing and transformation | Industry standard for Bash JSON processing, already a dependency |
| bash | 4.0+ | Script execution | Already validated in Phase 1 check_deps.sh |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| date | Timestamp generation (RFC 3339 for API, epoch for cache) | Time window calculations, API query parameters |
| stat | File modification time (via get_file_mtime) | Already in helpers.sh |
| mktemp | Temporary files for atomic writes | Already in cache.sh |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq for JSONL parsing | grep + awk | jq handles nested JSON safely; grep/awk brittle with JSON escaping |
| while-read loop for JSONL | jq --slurp | while-read is memory efficient for large log files; slurp loads all into memory |
| curl | wget | curl has better status code capture (`-w '%{http_code}'`); already a Phase 1 dependency |

## Architecture Patterns

### Recommended Script Structure
```
scripts/
├── helpers.sh          # (Phase 1) Cross-platform utilities
├── cache.sh            # (Phase 1) Cache read/write/lock
├── credentials.sh      # (Phase 1) API key loading
├── check_deps.sh       # (Phase 1) Dependency checker
├── detect_mode.sh      # (NEW) Mode auto-detection
├── api_fetch.sh        # (NEW) Admin API client
├── local_parse.sh      # (NEW) JSONL log parser
└── fetch.sh            # (NEW) Orchestrator: detect -> fetch -> cache
```

### Pattern 1: Admin API Request with Error Handling
**What:** Fetch from Anthropic Admin API with proper headers, status code capture, and pagination.
**When to use:** Every API call in api_fetch.sh.
**Example:**
```bash
# Source: https://platform.claude.com/docs/en/build-with-claude/usage-cost-api
local response http_code
response=$(curl -s -w "\n%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $api_key" \
    "$url")

# Split response body and status code
http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

case "$http_code" in
    200) ;; # success
    401|403) echo '{"error":{"code":"auth_failed","message":"Invalid or insufficient API key"}}' ; return 1 ;;
    429)     echo '{"error":{"code":"rate_limited","message":"Rate limited — increase refresh interval"}}' ; return 1 ;;
    5*)      echo '{"error":{"code":"api_unavailable","message":"Anthropic API unavailable"}}' ; return 1 ;;
    *)       echo '{"error":{"code":"unknown","message":"HTTP '"$http_code"'"}}' ; return 1 ;;
esac
```

### Pattern 2: JSONL Line-by-Line Parsing
**What:** Process JSONL files line by line using while-read + jq per line.
**When to use:** Parsing Claude Code session logs in local_parse.sh.
**Example:**
```bash
# Memory-efficient line-by-line parsing
while IFS= read -r line; do
    # Skip non-assistant entries
    local entry_type
    entry_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    [[ "$entry_type" != "assistant" ]] && continue

    # Extract model and token counts
    local model input_tokens output_tokens
    model=$(printf '%s' "$line" | jq -r '.message.model // empty' 2>/dev/null) || continue
    input_tokens=$(printf '%s' "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
    output_tokens=$(printf '%s' "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null)
    timestamp=$(printf '%s' "$line" | jq -r '.timestamp // empty' 2>/dev/null)

    # Accumulate...
done < "$jsonl_file"
```

### Pattern 3: Pagination Loop
**What:** Follow `has_more` / `next_page` pattern for Admin API pagination.
**When to use:** Any endpoint that may return paginated results.
**Example:**
```bash
local page_token=""
local all_data="[]"

while true; do
    local url="${base_url}?starting_at=${start}&ending_at=${end}&bucket_width=1d&group_by[]=model"
    [[ -n "$page_token" ]] && url="${url}&page=${page_token}"

    local result
    result=$(fetch_api "$url" "$api_key") || return 1

    # Merge data arrays
    all_data=$(printf '%s\n%s' "$all_data" "$result" | jq -s '.[0] + (.[1].data // [])')

    # Check pagination
    local has_more
    has_more=$(printf '%s' "$result" | jq -r '.has_more')
    [[ "$has_more" != "true" ]] && break

    page_token=$(printf '%s' "$result" | jq -r '.next_page')
done
```

### Anti-Patterns to Avoid
- **Passing API key as URL parameter:** Visible in process list and server logs. Always use `x-api-key` header.
- **Synchronous API calls from status bar:** Status bar scripts run every few seconds. Never call API from them -- read cache only.
- **jq --slurp on large JSONL files:** Session logs can be 100MB+. Use line-by-line processing.
- **Hardcoding API base URL:** Use a variable so it can be overridden for testing.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing in Bash | sed/awk/grep on JSON | jq | JSON has nested structures, escaping, arrays -- regex fails |
| Atomic file writes | Direct echo > file | cache_write() from cache.sh | Race conditions with concurrent readers |
| File locking | Custom flock wrapper | acquire_lock()/release_lock() from cache.sh | Cross-platform already handled |
| API key loading | Custom file reading | load_api_key() from credentials.sh | Permission checking already handled |
| Platform detection | Inline uname checks | get_platform() from helpers.sh | Cached result, consistent behavior |
| RFC 3339 date formatting | Manual string building | `date -u +"%Y-%m-%dT%H:%M:%SZ"` | Standard, cross-platform with minor GNU/BSD handling |

## Common Pitfalls

### Pitfall 1: JSONL Log Path Uses Encoded Directory Names
**What goes wrong:** Looking for session files at `~/.claude/projects/*/sessions/*.jsonl` but they are actually at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` where `<encoded-cwd>` replaces path separators with hyphens.
**Why it happens:** The CONTEXT.md specifies `~/.claude/projects/*/sessions/*.jsonl` but actual Claude Code stores files differently.
**How to avoid:** Use glob `~/.claude/projects/*/*.jsonl` to find session files. The directory names are encoded paths (e.g., `-home-ubuntu-myproject`), not human-readable project names. There is no `sessions/` subdirectory -- JSONL files are directly inside the project directory.
**Warning signs:** Empty results from log parsing, "no sessions found" errors.

### Pitfall 2: JSONL Schema Varies Between Entry Types
**What goes wrong:** Assuming all JSONL lines have the same schema. They don't.
**Why it happens:** The session file contains multiple entry types: `queue-operation`, `user`, `assistant`, `progress`, `summary`.
**How to avoid:** Filter for `type == "assistant"` entries which contain `.message.model` and `.message.usage` fields. Other types don't have token data.
**Warning signs:** jq errors about null values, missing fields.

### Pitfall 3: GNU vs BSD Date Command Differences
**What goes wrong:** `date -d` works on Linux but not macOS. `date -v` works on macOS but not Linux.
**Why it happens:** Different implementations of the `date` command.
**How to avoid:** For "7 days ago" calculations:
- Linux: `date -u -d "7 days ago" +%s`
- macOS: `date -u -v-7d +%s`
Use `get_platform()` to branch.
**Warning signs:** "illegal option" errors on macOS.

### Pitfall 4: curl Response Body vs Status Code Separation
**What goes wrong:** Capturing HTTP status code clobbers the response body, or vice versa.
**Why it happens:** curl outputs both to stdout by default.
**How to avoid:** Use `curl -s -w "\n%{http_code}"` pattern -- response body followed by newline and status code on last line. Split with `tail -1` for code and `sed '$d'` for body.
**Warning signs:** JSON parse errors because status code is appended to body.

### Pitfall 5: Admin API Cost Report Returns Cents Not Dollars
**What goes wrong:** Displaying `$12345` instead of `$123.45` to the user.
**Why it happens:** The `amount` field in cost report is in lowest currency units (cents) as a decimal string. "123.45" means $1.2345.
**How to avoid:** Divide by 100 when converting to display value. Use jq arithmetic: `amount | tonumber / 100`.
**Warning signs:** Costs appear 100x too high.

### Pitfall 6: Model Names in JSONL vs API Differ
**What goes wrong:** Grouping fails because API returns `claude-opus-4-6` while user expects "opus".
**Why it happens:** JSONL files use full model identifiers like `claude-opus-4-6`, `claude-sonnet-4-20250514`. Admin API `group_by[]=model` returns the same full identifiers.
**How to avoid:** Normalize model names in both parsers: extract the family name (opus, sonnet, haiku) from the full model string using pattern matching: `case "$model" in *opus*) normalized="opus" ;; *sonnet*) normalized="sonnet" ;; *haiku*) normalized="haiku" ;; esac`.
**Warning signs:** Per-model data shows full model versions instead of clean labels.

## Code Examples

### Admin API: Fetch Weekly Usage by Model
```bash
# Source: https://platform.claude.com/docs/en/build-with-claude/usage-cost-api
# Get daily usage for the last 7 days, grouped by model
local start_date end_date
if [[ "$(get_platform)" == "darwin" ]]; then
    start_date=$(date -u -v-7d +"%Y-%m-%dT00:00:00Z")
    end_date=$(date -u +"%Y-%m-%dT23:59:59Z")
else
    start_date=$(date -u -d "7 days ago" +"%Y-%m-%dT00:00:00Z")
    end_date=$(date -u +"%Y-%m-%dT23:59:59Z")
fi

curl -s -w "\n%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $api_key" \
    "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${start_date}&ending_at=${end_date}&group_by[]=model&bucket_width=1d"
```

### Admin API: Fetch Cost Report
```bash
# Source: https://platform.claude.com/docs/en/api/admin/cost_report
curl -s -w "\n%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $api_key" \
    "https://api.anthropic.com/v1/organizations/cost_report?starting_at=${start_date}&ending_at=${end_date}&bucket_width=1d&group_by[]=description"
```

### Admin API: Get Organization Info (for email/name)
```bash
# Source: https://platform.claude.com/docs/en/build-with-claude/administration-api
# /v1/organizations/me returns org name; /v1/organizations/users lists members with emails
curl -s -w "\n%{http_code}" \
    -H "anthropic-version: 2023-06-01" \
    -H "x-api-key: $api_key" \
    "https://api.anthropic.com/v1/organizations/users?limit=1"
```

### JSONL: Extract Token Usage from Session File
```bash
# Verified from live session files on this system
# Assistant entries have: .type="assistant", .message.model, .message.usage.{input_tokens, output_tokens}
jq -r 'select(.type == "assistant") |
    [.timestamp, .message.model,
     (.message.usage.input_tokens // 0),
     (.message.usage.output_tokens // 0)] |
    @tsv' "$jsonl_file"
```

### Cross-Platform Date Calculation
```bash
# Get epoch timestamp for N days ago
get_epoch_days_ago() {
    local days="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        date -u -v-"${days}d" +%s
    else
        date -u -d "${days} days ago" +%s
    fi
}

# Get RFC 3339 date for N days ago
get_rfc3339_days_ago() {
    local days="$1"
    if [[ "$(get_platform)" == "darwin" ]]; then
        date -u -v-"${days}d" +"%Y-%m-%dT00:00:00Z"
    else
        date -u -d "${days} days ago" +"%Y-%m-%dT00:00:00Z"
    fi
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No usage API | Admin API Usage + Cost endpoints | 2024-2025 | Programmatic access to org-level usage and spend data |
| No per-user Claude Code analytics | Claude Code Analytics API (`/v1/organizations/usage_report/claude_code`) | 2025 | Per-user daily metrics including estimated costs -- but requires admin key |
| Manual token counting from API responses | Server-side usage tracking in session JSONL | 2025 | Accurate token counts including cache tokens logged automatically |

**Important discovery:** The Claude Code Analytics API (`/v1/organizations/usage_report/claude_code`) provides per-user estimated costs and productivity metrics. This is MORE useful than the generic usage endpoint for org users running Claude Code. However, it still requires an admin key and is org-only.

**Deprecated/outdated:**
- The CONTEXT.md references `/v1/organizations/members` for email -- the actual endpoint is `/v1/organizations/users`
- The CONTEXT.md references `~/.claude/projects/*/sessions/*.jsonl` -- the actual path is `~/.claude/projects/*/*.jsonl` (no `sessions/` subdirectory)

## Open Questions

1. **Plan limits for subscription users**
   - What we know: Claude Pro/Max plans have usage limits (hours/day or tokens/period) that reset weekly
   - What's unclear: No public API or documentation specifying exact token limits per plan tier
   - Recommendation: Hardcode approximate values in a lookup table, document they are approximate. Default to "max_5x" plan. Allow user to set plan type via `@claudux_plan` tmux option.

2. **JSONL schema stability**
   - What we know: Current format has `type`, `message.model`, `message.usage.*`, `timestamp` fields
   - What's unclear: Whether Anthropic considers this a stable interface
   - Recommendation: Add a comment noting schema may change. Fail gracefully if fields are missing (use `// 0` and `// empty` defaults in jq). Add version detection via the `version` field in JSONL entries.

3. **Billing period boundaries for org users**
   - What we know: The Admin API lets you specify arbitrary date ranges
   - What's unclear: How to determine the org's actual billing cycle start date
   - Recommendation: Use rolling windows (last 7 days for weekly, last 30 days for monthly) rather than trying to align to billing cycles. This is simpler and more universally correct.

4. **Account email for local mode users**
   - What we know: Org mode can use `/v1/organizations/users` endpoint
   - What's unclear: Where local/subscription users' email is stored
   - Recommendation: Try `~/.claude/settings.json` or `~/.claude/config.json`. If not found, display "local" instead of an email address.

## Sources

### Primary (HIGH confidence)
- [Anthropic Admin API - Usage Report](https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-messages-usage-report) - Full endpoint schema, parameters, response format
- [Anthropic Usage and Cost API Guide](https://platform.claude.com/docs/en/build-with-claude/usage-cost-api) - Overview, examples, pagination, FAQ
- [Anthropic Admin API - Cost Report](https://platform.claude.com/docs/en/api/admin/cost_report) - Cost endpoint schema
- [Anthropic Admin API Overview](https://platform.claude.com/docs/en/build-with-claude/administration-api) - Members endpoint, org info, authentication
- [Claude Code Analytics API](https://platform.claude.com/docs/en/api/claude-code-analytics-api) - Per-user Claude Code metrics
- Live JSONL inspection on this system (`~/.claude/projects/`) - Verified actual file format

### Secondary (MEDIUM confidence)
- [DuckDB Analysis of Claude Code Logs](https://liambx.com/blog/claude-code-log-analysis-with-duckdb) - JSONL schema details, field names confirmed
- [Claude Code Hidden History](https://kentgigger.com/posts/claude-code-conversation-history) - Directory structure, file organization

### Tertiary (LOW confidence)
- Plan limits for subscription tiers - No official source found, values are approximate community knowledge

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - curl, jq, bash are the established tools with Phase 1 precedent
- Architecture: HIGH - API endpoints fully documented, JSONL format verified from live files
- Pitfalls: HIGH - Verified path differences and schema variations from actual system inspection

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (API endpoints stable; JSONL format may change)
