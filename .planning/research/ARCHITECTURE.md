# Architecture Patterns

**Domain:** tmux status bar plugin / Claude API monitoring
**Researched:** 2026-03-10

## Recommended Architecture

Claudux follows the established TPM (Tmux Plugin Manager) plugin pattern: a shell-based plugin with a `.tmux` entry point that registers custom format strings, backed by scripts that fetch and cache Anthropic API data, then render it as compact status bar segments.

```
~/.tmux/plugins/claudux/
|
|-- claudux.tmux              # Entry point: registers format strings with tmux
|-- scripts/
|   |-- claudux.sh            # Main orchestrator: cache check -> fetch -> render
|   |-- api.sh                # Anthropic API client (curl wrapper, auth, error handling)
|   |-- cache.sh              # Cache read/write/TTL logic (file-based)
|   |-- render.sh             # Progress bar rendering, color formatting
|   |-- helpers.sh            # Shared utilities (tmux option getters, etc.)
|-- config/
|   |-- defaults.sh           # Default option values
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `claudux.tmux` | Plugin initialization: reads `status-right`/`status-left`, replaces `#{claudux_*}` placeholders with `#(scripts/claudux.sh ...)` shell commands, writes options back | tmux server (via `tmux show-option` / `tmux set-option`) |
| `scripts/claudux.sh` | Main dispatcher: called by tmux on every status refresh. Checks cache freshness, delegates to api.sh or cache.sh, delegates to render.sh, outputs a formatted string to stdout | cache.sh, api.sh, render.sh |
| `scripts/api.sh` | Anthropic API communication: constructs requests, handles auth, parses JSON responses, extracts quota/usage data | Anthropic API (HTTPS), cache.sh (writes fetched data) |
| `scripts/cache.sh` | File-based cache: stores raw API responses with timestamps, checks TTL, returns cached data or signals stale | Filesystem (temp files in `/tmp/claudux/` or `$XDG_CACHE_HOME/claudux/`) |
| `scripts/render.sh` | Output formatting: takes raw usage numbers, renders Unicode progress bars, applies tmux color codes, formats reset dates | helpers.sh (for color/style options) |
| `scripts/helpers.sh` | Shared utilities: `get_tmux_option` wrapper, path resolution, platform detection | tmux server (read-only option queries) |
| `config/defaults.sh` | Default configuration values for all `@claudux_*` options | Sourced by helpers.sh |

### Data Flow

```
tmux status refresh (every N seconds, controlled by status-interval)
    |
    v
tmux evaluates status-right/status-left containing #(~/.tmux/plugins/claudux/scripts/claudux.sh <segment>)
    |
    v
claudux.sh receives segment argument (e.g., "quota_weekly", "quota_monthly", "model_usage", "reset_date", "email")
    |
    v
cache.sh: Is cached data fresh (within TTL)?
    |                    |
    YES                  NO
    |                    |
    v                    v
Read cache file      api.sh: curl Anthropic API
    |                    |
    |                    v
    |              Parse JSON (jq) -> extract relevant fields
    |                    |
    |                    v
    |              cache.sh: Write to cache file with timestamp
    |                    |
    +--------------------+
    |
    v
render.sh: Format output (progress bar, colors, text)
    |
    v
stdout -> tmux renders in status bar
```

### API Data Sources (Two Tiers)

**Tier 1: Rate limit headers (lightweight, no Admin key needed)**
- Source: Any Messages API call response headers
- Headers: `anthropic-ratelimit-requests-remaining`, `anthropic-ratelimit-tokens-remaining`, `anthropic-ratelimit-*-reset`
- Limitation: Requires making an actual API call; only shows per-minute rate limits, not spend/quota
- Use case: Real-time rate limit status display

**Tier 2: Admin API (comprehensive, requires Admin API key)**
- Endpoint: `GET /v1/organizations/usage_report/messages` -- token usage by model, workspace, time bucket
- Endpoint: `GET /v1/organizations/cost_report` -- cost in USD by service
- Endpoint: `GET /v1/organizations/usage_report/claude_code` -- Claude Code specific analytics
- Requirement: Admin API key (`sk-ant-admin...`), organization account
- Use case: Quota consumption, spend tracking, model-specific breakdowns

**Recommended approach:** Support both tiers. Default to a lightweight "ping" approach (a minimal API call to read headers) for rate limit data, and use Admin API for rich quota/spend data when an admin key is configured. The plugin should gracefully degrade: if no Admin key is provided, show rate limit data only.

**Confidence: HIGH** -- Verified against official Anthropic API documentation at platform.claude.com/docs.

## Patterns to Follow

### Pattern 1: TPM Format String Registration

**What:** The standard tmux plugin pattern for exposing custom status bar variables. The `.tmux` entry point reads the current `status-right` and `status-left` values, uses sed to replace custom `#{claudux_*}` placeholders with `#(path/to/script.sh arg)` shell command invocations, then writes the modified string back.

**When:** Plugin initialization (when TPM sources the plugin).

**Why this matters:** tmux has no native "plugin variable" system. The `#{...}` syntax only works for built-in tmux variables. Plugins simulate custom variables by doing string replacement at load time, turning `#{claudux_quota}` into `#(/path/to/claudux/scripts/claudux.sh quota)` which tmux natively evaluates as a shell command.

**Confidence: HIGH** -- This is the pattern used by tmux-battery, tmux-cpu, tmux-plugin-sysstat, and the Dracula tmux theme. Verified across multiple official tmux-plugins org repositories.

**Example:**
```bash
#!/usr/bin/env bash
# claudux.tmux -- Plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define format string mappings
declare -A CLAUDUX_FORMATS=(
    ["#{claudux_quota_weekly}"]="#($CURRENT_DIR/scripts/claudux.sh quota_weekly)"
    ["#{claudux_quota_monthly}"]="#($CURRENT_DIR/scripts/claudux.sh quota_monthly)"
    ["#{claudux_model_sonnet}"]="#($CURRENT_DIR/scripts/claudux.sh model_sonnet)"
    ["#{claudux_reset_date}"]="#($CURRENT_DIR/scripts/claudux.sh reset_date)"
    ["#{claudux_email}"]="#($CURRENT_DIR/scripts/claudux.sh email)"
)

do_interpolation() {
    local option="$1"
    local value
    value="$(tmux show-option -gqv "$option")"
    for placeholder in "${!CLAUDUX_FORMATS[@]}"; do
        value="${value//$placeholder/${CLAUDUX_FORMATS[$placeholder]}}"
    done
    tmux set-option -gq "$option" "$value"
}

do_interpolation "status-right"
do_interpolation "status-left"
```

### Pattern 2: File-Based Cache with TTL

**What:** Store API responses as JSON files with a companion timestamp file. On each status refresh, check file modification time against TTL before making a new API call. Use a single cache file for all data (one API call fetches everything needed).

**When:** Every status bar refresh (every `status-interval` seconds).

**Why:** The tmux status bar refreshes frequently (default every 15 seconds). Making an API call on every refresh would be wasteful and risks rate limiting. The Anthropic API recommends polling at most once per minute. A 5-minute TTL is sensible for quota data that changes slowly.

**Confidence: HIGH** -- Standard pattern across tmux-powerkit, tmux-plugin-sysstat, and community best practices.

**Example:**
```bash
#!/usr/bin/env bash
# cache.sh

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
CACHE_FILE="$CACHE_DIR/api_response.json"
CACHE_TTL=300  # 5 minutes in seconds

is_cache_fresh() {
    [[ -f "$CACHE_FILE" ]] || return 1
    local now file_age
    now=$(date +%s)
    file_age=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null)
    (( now - file_age < CACHE_TTL ))
}

read_cache() {
    cat "$CACHE_FILE" 2>/dev/null
}

write_cache() {
    mkdir -p "$CACHE_DIR"
    echo "$1" > "$CACHE_FILE"
}
```

### Pattern 3: Segment-Based Dispatcher

**What:** A single main script (`claudux.sh`) that receives a segment name as its first argument and dispatches to the appropriate rendering function. This avoids spawning multiple independent scripts for each format string.

**When:** Called by tmux for each `#(...)` invocation in the status line.

**Why:** Each `#(...)` in the status line spawns a separate shell process. By sharing the cache across all invocations and keeping scripts fast (read cached file, format output, exit), the overhead stays minimal. The first invocation within a refresh cycle that finds stale cache triggers the API call; subsequent invocations in the same cycle read the freshly written cache.

**Confidence: HIGH** -- This is how tmux-cpu and tmux-battery structure their scripts.

**Example:**
```bash
#!/usr/bin/env bash
# claudux.sh -- Main dispatcher

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/cache.sh"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/render.sh"

SEGMENT="${1:-quota_weekly}"

# Ensure fresh data
if ! is_cache_fresh; then
    source "$CURRENT_DIR/api.sh"
    data=$(fetch_usage_data)
    write_cache "$data"
fi

cached_data=$(read_cache)

case "$SEGMENT" in
    quota_weekly)   render_quota_bar "$cached_data" "weekly" ;;
    quota_monthly)  render_quota_bar "$cached_data" "monthly" ;;
    model_sonnet)   render_model_bar "$cached_data" "sonnet" ;;
    reset_date)     render_reset_date "$cached_data" ;;
    email)          render_email "$cached_data" ;;
    *)              echo "?" ;;
esac
```

### Pattern 4: User Options via tmux Variables

**What:** All configuration is stored as tmux user options (`@claudux_*`) readable with `tmux show-option -gqv`. The plugin reads these at both initialization time and render time.

**When:** Any time the plugin needs configuration values.

**Why:** This is the standard TPM ecosystem convention. Users configure plugins in their `.tmux.conf` with `set -g @claudux_api_key "..."` and the plugin reads them with `tmux show-option`. No separate config file needed, though the plugin should support `ANTHROPIC_API_KEY` env var as a fallback for the API key specifically.

**Confidence: HIGH** -- Universal pattern across all TPM plugins.

**Example options:**
```bash
# .tmux.conf user configuration
set -g @claudux_api_key ""                    # Admin API key (falls back to $ANTHROPIC_API_KEY)
set -g @claudux_cache_ttl "300"               # Cache TTL in seconds
set -g @claudux_bar_length "10"               # Progress bar character width
set -g @claudux_bar_fill "▓"                  # Progress bar fill character
set -g @claudux_bar_empty "░"                 # Progress bar empty character
set -g @claudux_accent_color "colour39"       # Accent color for labels
set -g @claudux_show_email "yes"              # Whether to show account email
set -g @claudux_show_reset "yes"              # Whether to show reset times
```

### Pattern 5: Portable Shell with Platform Detection

**What:** Use POSIX-compatible bash (minimum bash 3.2 for macOS compatibility). Detect platform for `stat` command differences (GNU vs BSD), `date` formatting, and available JSON parsers.

**When:** During cache operations and any platform-dependent behavior.

**Why:** tmux users span Linux and macOS. GNU `stat -c %Y` vs BSD `stat -f %m` is the most common portability issue in tmux plugins.

**Confidence: HIGH** -- Documented across tmux-battery, tmux-cpu, and tmux-plugin-sysstat.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Heavy Runtime Dependencies

**What:** Requiring Python, Node.js, or other interpreters to run on every status refresh.
**Why bad:** Each `#(...)` spawns a new process. Python/Node startup time (100-500ms) is unacceptable for a status bar that refreshes every 5-15 seconds with multiple segments. The user sees a blank or flickering status bar while scripts load.
**Instead:** Use bash + curl + jq. These are near-instant to start and universally available. jq is the only non-standard dependency and is widely packaged. If jq is not available, provide a fallback using grep/sed/awk for basic JSON parsing, or bundle a lightweight JSON parser.

### Anti-Pattern 2: Separate API Calls Per Segment

**What:** Each format string (`#{claudux_quota_weekly}`, `#{claudux_quota_monthly}`, etc.) triggers its own independent API call.
**Why bad:** If 5 segments are displayed, that is 5 API calls per refresh cycle. This wastes rate limit budget and multiplies latency.
**Instead:** One API call per cache refresh, stored in a shared cache file. All segments read from the same cache. Use a file lock (flock) or atomic write to prevent race conditions when multiple segments try to refresh simultaneously.

### Anti-Pattern 3: Blocking on Slow API Responses

**What:** The status bar script waits synchronously for the API response, blocking tmux rendering.
**Why bad:** If the Anthropic API is slow (timeout, network issue), the entire tmux status bar freezes. tmux evaluates `#(...)` commands synchronously on each refresh.
**Instead:** Return cached/stale data immediately. Trigger background refresh (`curl ... &`) and update cache for the next cycle. If no cache exists at all (first run), show a placeholder like "loading..." and let the background fetch populate the cache. Note: tmux does run `#()` commands asynchronously (with a 1-second timeout by default), but long-running commands still produce blank output until they complete.

### Anti-Pattern 4: Storing API Keys in Plugin Files

**What:** Hardcoding or storing the Anthropic API key within the plugin directory.
**Why bad:** Plugin directories are often version-controlled (dotfiles repos). API keys would be committed.
**Instead:** Read from tmux option (`@claudux_api_key`), then fall back to environment variable (`$ANTHROPIC_API_KEY`), then fall back to a standard config file (`~/.config/claudux/config` or `~/.anthropic/api_key`). Never store keys in the plugin tree.

### Anti-Pattern 5: Parsing JSON with sed/awk

**What:** Attempting to parse nested JSON API responses using only sed, awk, and grep.
**Why bad:** JSON is not a line-oriented format. Edge cases (nested objects, escaped characters, null values) cause silent failures. The Anthropic API responses have nested structures (e.g., model breakdowns with arrays of token objects).
**Instead:** Require `jq` as the JSON parser. It is available in every major package manager (`apt`, `brew`, `pacman`, `dnf`). Check for jq at plugin init time and print a clear error message if missing. For ultra-minimal environments, consider bundling a tiny JSON extractor in pure bash as a fallback, but jq should be the primary path.

## Scalability Considerations

This plugin is a local tool running on a single developer's machine. "Scalability" here means: how well does it handle edge cases and growth in usage.

| Concern | Single developer | Team (shared dotfiles) | Open source distribution |
|---------|-----------------|----------------------|-------------------------|
| API key management | Env var works fine | Per-user env vars, document clearly | Support multiple auth methods (option, env, file) |
| Cache location | `/tmp/claudux/` is fine | Need user-specific paths (`$HOME/.cache/claudux/`) | Use `$XDG_CACHE_HOME` with fallback |
| Error display | Show error inline in status bar | Same | Graceful degradation: show "N/A" not stack traces |
| Multiple tmux sessions | All read same cache (good) | Same | Document that cache is shared across sessions |
| API changes | Pin API version header | Same | Version-check and warn on breaking changes |

## Suggested Build Order

The architecture has clear dependency layers. Build bottom-up:

```
Phase 1: Foundation
    helpers.sh (tmux option reading, path utils)
    config/defaults.sh (default option values)
    cache.sh (file-based cache with TTL)
    |
Phase 2: API Integration
    api.sh (Anthropic API client with auth + error handling)
    Depends on: helpers.sh (for reading @claudux_api_key), cache.sh (for writing)
    |
Phase 3: Rendering
    render.sh (progress bars, color formatting, date formatting)
    Depends on: helpers.sh (for reading display options)
    |
Phase 4: Orchestration
    claudux.sh (main dispatcher, ties cache + api + render together)
    Depends on: all of the above
    |
Phase 5: Plugin Integration
    claudux.tmux (TPM entry point, format string registration)
    Depends on: claudux.sh being functional
    |
Phase 6: Polish
    Error handling, graceful degradation, installation docs, README
    Depends on: everything working end-to-end
```

**Rationale for this order:**
1. Foundation scripts can be tested independently with mock data
2. API integration can be tested against real Anthropic endpoints in isolation
3. Rendering can be tested with hardcoded data, producing visible output immediately
4. The dispatcher ties everything together -- this is the integration test
5. The .tmux entry point is the last step because it only does string replacement and can be tested quickly
6. Polish comes last because you need the full pipeline working to identify real edge cases

## Key Architectural Decision: Bash vs. Other Languages

**Decision: Use Bash (with jq for JSON)**

**Rationale:**
- tmux plugins are conventionally shell scripts. The entire TPM ecosystem (tmux-battery, tmux-cpu, tmux-sensible, tmux-resurrect, etc.) is bash.
- Process startup cost matters enormously here. The status bar evaluates `#(...)` commands frequently. Bash + curl + jq cold-start in under 10ms. Python takes 50-200ms. Node takes 100-500ms.
- The logic is simple: fetch, cache, format, output. There is no complex state, no concurrency model, no framework needed.
- The only non-trivial operation (JSON parsing) is handled by jq, which is purpose-built for this.
- Users expect to install a tmux plugin with TPM and have it work. Adding a Python/Node runtime dependency breaks this expectation.

**When to reconsider:** If the rendering logic becomes extremely complex (e.g., sparkline graphs, sophisticated Unicode layout), a compiled helper binary (Go or Rust, statically linked) could be warranted. But for progress bars and text formatting, bash is more than sufficient.

**Confidence: HIGH** -- Based on analysis of the entire tmux-plugins ecosystem.

## Sources

- [TPM - Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) -- Plugin architecture and lifecycle (HIGH confidence)
- [tmux-example-plugin](https://github.com/tmux-plugins/tmux-example-plugin) -- Reference plugin structure (HIGH confidence)
- [TPM: How to Create a Plugin](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md) -- Plugin conventions (HIGH confidence)
- [tmux-battery](https://github.com/tmux-plugins/tmux-battery) -- Format string interpolation pattern (HIGH confidence)
- [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu) -- Multi-metric status bar plugin pattern (HIGH confidence)
- [tmux-plugin-sysstat](https://github.com/samoshkin/tmux-plugin-sysstat) -- Advanced templating and caching patterns (HIGH confidence)
- [tmux-status-variables](https://github.com/odedlaz/tmux-status-variables) -- Custom variable registration mechanism (MEDIUM confidence)
- [Dracula tmux theme](https://deepwiki.com/dracula/tmux/3-plugin-reference) -- Widget dispatch pattern with `#()` wrapping (MEDIUM confidence)
- [tmux-powerkit](https://github.com/fabioluciano/tmux-powerkit) -- Stale-while-revalidate caching strategy (MEDIUM confidence)
- [Anthropic Usage and Cost API](https://platform.claude.com/docs/en/api/usage-cost-api) -- Official Admin API documentation (HIGH confidence)
- [Anthropic Rate Limits](https://platform.claude.com/docs/en/api/rate-limits) -- Rate limit headers and tiers (HIGH confidence)
- [Claude Code Analytics API](https://platform.claude.com/docs/en/api/claude-code-analytics-api) -- Claude Code usage metrics (HIGH confidence)
- [tmux Formats Wiki](https://github.com/tmux/tmux/wiki/Formats) -- Native format string system (HIGH confidence)
- [Tao of tmux - Status Bar](https://tao-of-tmux.readthedocs.io/en/latest/manuscript/09-status-bar.html) -- Status bar fundamentals (HIGH confidence)
