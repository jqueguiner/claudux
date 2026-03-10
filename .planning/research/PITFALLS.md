# Pitfalls Research

**Domain:** tmux status bar plugin / Claude API monitoring
**Researched:** 2026-03-10
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Assuming Standard API Keys Can Fetch Usage/Quota Data

**What goes wrong:**
The project's core purpose is displaying consumption quotas, but the Anthropic Usage and Cost API (`/v1/organizations/usage_report/messages` and `/v1/organizations/cost_report`) requires an **Admin API key** (prefix `sk-ant-admin...`), not a standard API key (prefix `sk-ant-api...`). A standard API key can only make inference calls to Claude models. The Admin API is also unavailable for individual accounts -- it requires an Organization.

**Why it happens:**
Developers assume that because they have an API key, they can query their own billing data. Anthropic separates inference keys from administrative keys. Only organization members with the admin role can provision Admin API keys through the Claude Console.

**How to avoid:**
- Document upfront that Claudux requires an Admin API key, not a standard API key
- Detect the key type at startup (check `sk-ant-admin` prefix) and show a clear error message if the wrong key type is used
- Provide setup instructions in README for generating an Admin API key via Claude Console > Settings > Admin Keys
- Design a fallback mode: if only a standard API key is available, extract rate-limit data from response headers (`anthropic-ratelimit-*` headers returned on every API call) instead of full billing data

**Warning signs:**
- 401/403 errors when calling the usage endpoint
- Users filing issues saying "it doesn't work with my API key"
- Zero usage data returned despite active API usage

**Phase to address:**
Phase 1 (Core API Integration) -- this is a day-one architectural decision that shapes the entire data layer.

---

### Pitfall 2: Blocking tmux Status Bar With Synchronous API Calls

**What goes wrong:**
tmux executes shell commands in the status line via `#(command ...)` syntax. Every status bar refresh forks a child process. If that process makes a blocking HTTP call (e.g., `curl` to the Anthropic API), the entire tmux session freezes or stutters until the response arrives. At 429 rate-limit or network timeout, the terminal becomes unusable.

**Why it happens:**
The naive approach is: status bar calls script, script calls API, script formats output. This works in testing on fast connections but fails in production when the API is slow, rate-limited, or unreachable. tmux's fork() overhead compounds the problem -- with large scrollback buffers (10M+ lines), each fork copies page table entries, adding 45ms+ per status refresh even before the HTTP call.

**How to avoid:**
- **Never call the API from the status bar script directly.** The status bar script must only read from a local cache file and format output
- Run a separate background daemon/cron job that fetches API data and writes to a cache file (e.g., `/tmp/claudux-$UID/cache.json`)
- The status bar script reads the cache file (fast filesystem read, no network I/O)
- Set `status-interval` to 5-15 seconds minimum; the cache file can be updated on its own schedule (every 5-10 minutes)
- Add `--connect-timeout 5 --max-time 10` to all `curl` calls in the background fetcher

**Warning signs:**
- Terminal cursor stutters when status bar updates
- tmux becomes sluggish with large scrollback
- CPU spikes coinciding with status-interval refresh
- Users reporting "tmux freezes for a second" periodically

**Phase to address:**
Phase 1 (Architecture) -- the cache-based architecture must be the foundation, not retrofitted.

---

### Pitfall 3: API Key Leaking Through Process List or Git History

**What goes wrong:**
When a shell script passes an API key as a command-line argument (e.g., `curl -H "x-api-key: sk-ant-admin-..."`) rather than reading it from a file or environment variable, any user on the system can see the key by running `ps aux`. Additionally, if the key is stored in a config file that gets committed to git, it becomes permanently exposed in git history even after deletion.

**Why it happens:**
tmux plugins often store configuration in `~/.tmux.conf` or a separate config file. Developers testing locally hardcode keys for convenience, then ship that pattern. The `#(command)` status bar syntax means the full command (including arguments) is visible in the process tree.

**How to avoid:**
- Read the API key from an environment variable (`$ANTHROPIC_ADMIN_API_KEY`) or a dedicated file (`~/.config/claudux/key`) with `chmod 600` permissions
- Never pass the key as a CLI argument; use `curl --header @-` or write it via stdin
- Ship a `.gitignore` that excludes config files containing keys
- Validate on startup that the key file has restrictive permissions (warn if group/world readable)
- Document the security model in the README

**Warning signs:**
- API key visible in `ps aux | grep curl` output
- Config file containing key does not have restrictive permissions
- Key appears in git log

**Phase to address:**
Phase 1 (Configuration & Auth) -- security must be baked in from the first line of code.

---

### Pitfall 4: Confusing API Billing Quotas vs. Claude Pro/Max Subscription Quotas

**What goes wrong:**
The project description mentions "weekly consumption quota" and "monthly consumption quota." These map to different systems:
- **API billing:** Monthly spend limits per tier (Tier 1: $100/mo, Tier 2: $500/mo, etc.), tracked via Admin API
- **Claude Pro/Max subscription:** Weekly active compute hour caps, accessible via `/status` command in Claude Code but with **no documented public API endpoint for programmatic access**
- **Rate limits:** Per-minute RPM/TPM/OTPM limits, available via response headers on every API call

Building features around the wrong quota concept leads to showing meaningless or misleading data.

**Why it happens:**
Anthropic's quota landscape is fragmented. The word "quota" means different things depending on context. The project spec says "weekly" which suggests Pro/Max subscription quotas, but the tooling available (Admin API) only exposes API billing data.

**How to avoid:**
- Clearly define in the project scope which quotas are being tracked: API billing spend limits, rate limits, or subscription quotas
- For **API billing** (monthly spend): Use the Admin API Cost endpoint (`/v1/organizations/cost_report`)
- For **rate limits** (per-minute): Parse `anthropic-ratelimit-*` response headers from any API call -- these are available with standard API keys
- For **subscription quotas** (weekly compute hours): There is no documented programmatic API as of March 2026. This may require scraping or may simply be out of scope
- Design the UI to clearly label what each progress bar represents

**Warning signs:**
- Users ask "why doesn't this show my Pro plan limits?"
- Progress bars show 0% when the user expects high usage (wrong data source)
- Confusion in issues between "rate limit" and "spend limit" and "subscription quota"

**Phase to address:**
Phase 0 (Requirements Clarification) -- must resolve which quotas to display before writing any code.

---

### Pitfall 5: Unicode Progress Bars Breaking Status Line Width Calculation

**What goes wrong:**
tmux miscalculates the display width of certain Unicode characters, causing the status bar to render incorrectly: truncated content, wrapped status lines, or status bar elements overlapping. Multi-byte emoji (e.g., battery icons, lightning bolts) are particularly problematic. The status line draws up to n-1 columns or wraps entirely.

**Why it happens:**
tmux calculates character width based on its internal Unicode width tables, which may disagree with the terminal emulator's rendering. Wide characters (CJK, emoji) occupy 2 cells but may be counted as 1, or vice versa. Different terminal emulators (iTerm2, Alacritty, Windows Terminal, kitty) handle this differently.

**How to avoid:**
- Use only single-width Unicode block characters for progress bars: `#`, `=`, `-`, `|`, or the half/full block characters `\u2588` (full block), `\u2591` (light shade), `\u2592` (medium shade), `\u2593` (dark shade). These are consistently single-width across terminals
- Avoid emoji entirely in the status bar (no battery icons, no lightning bolts, no flag emoji)
- Test on at least 3 terminal emulators (iTerm2/Terminal.app on macOS, GNOME Terminal on Linux, Windows Terminal via WSL)
- Provide a `--ascii` mode that uses only ASCII characters for maximum compatibility
- Set `status-left-length` and `status-right-length` generously (e.g., 120+) to prevent truncation

**Warning signs:**
- Status bar content disappears or wraps to next line
- Different rendering across terminals
- Users on Windows Terminal / SSH sessions reporting garbled output
- Status line "jumps" on refresh

**Phase to address:**
Phase 2 (Display/UI) -- when building the progress bar rendering.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded refresh intervals | Quick to implement | Users with different needs can't adjust; fast intervals waste API calls, slow intervals feel stale | Never -- make configurable from day one via tmux option `@claudux-refresh-interval` |
| Parsing JSON with grep/sed instead of jq | No dependency on jq | Breaks on any API response format change, edge cases with nested JSON, silent failures on malformed responses | Never -- require jq as a dependency; it's ubiquitous on dev machines |
| Single cache file for all data | Simple implementation | Race condition when background fetcher writes while status script reads; corrupt reads on partial writes | MVP only -- move to atomic writes (write to temp, then `mv`) immediately |
| Inline API key in tmux.conf | Easy setup | Key exposed in dotfiles repo, visible in tmux show-options | Never -- always use env var or external file reference |
| Monolithic status bar script | One script does everything | Hard to test, hard to customize which segments appear, hard to debug | MVP only -- split into modular segments by Phase 2 |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Anthropic Admin API | Using standard `sk-ant-api` key instead of `sk-ant-admin` key | Detect key type at startup; document Admin key requirement clearly |
| Anthropic Admin API | Not handling pagination (`has_more` / `next_page` in responses) | Always check `has_more` field and paginate; usage data can span many pages |
| Anthropic Admin API | Polling too frequently (the API recommends once per minute sustained) | Poll every 5-10 minutes for status bar use; cache aggressively |
| Anthropic Rate Limit Headers | Only checking `anthropic-ratelimit-tokens-remaining` | Check all headers: `requests-remaining`, `input-tokens-remaining`, `output-tokens-remaining`; the most restrictive limit is what the combined headers show |
| curl on macOS vs Linux | macOS ships LibreSSL curl; Linux ships OpenSSL curl; different TLS behavior | Use `--tlsv1.2` minimum; test on both platforms; avoid macOS-specific curl flags |
| jq on macOS | macOS does not ship jq by default | Document jq as a required dependency; check for it at plugin install and provide install instructions |
| tmux option storage | Using `set-option -g` when `set-option -g @claudux-key "value"` user options require the `@` prefix | All plugin-specific options must use `@` prefix per TPM convention |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Calling API from `#()` status command | Cursor stutter, 1-5s freezes | Background daemon + cache file architecture | Immediately on slow networks or API rate limits |
| Fork overhead with large scrollback | tmux slowdown proportional to scrollback size | Keep status scripts minimal (read file, format, print); avoid subshell commands; use `posix_spawn` patterns | At 10M+ lines scrollback; noticeable at 1M+ |
| Unconstrained status-right-length | Status bar content silently truncated at ~165 chars default | Set `status-right-length 200` explicitly in plugin init | When adding multiple stats segments |
| Cache file grows unbounded | Disk usage climbs, parse time increases | Write only current-period data to cache; rotate or overwrite on each fetch | After weeks of accumulated data if appending |
| Background fetcher spawns multiple instances | Multiple curl processes hitting API simultaneously; rate limit exhaustion | Use PID file or `flock` to ensure single instance; kill stale processes on startup | When user sources tmux.conf multiple times or has multiple tmux sessions |

## Security Mistakes

Domain-specific security issues beyond general practices.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Passing API key as curl CLI argument | Key visible in `ps aux` to any user on the system | Read key from file, pipe via stdin: `curl -H @/dev/stdin <<< "x-api-key: $(cat keyfile)"` or use `--config` |
| Storing Admin API key in tmux.conf | Key committed to dotfiles repos; Admin keys have full org management access (can delete members, create keys) | Store in `~/.config/claudux/admin-key` with `chmod 600`; reference path in tmux.conf, not the key itself |
| Cache file world-readable | Other users can read org usage data and infer billing/usage patterns | Create cache in `/tmp/claudux-$UID/` with `umask 077`; verify permissions on startup |
| Not validating API responses before caching | Malicious or corrupted response stored and displayed | Validate JSON structure with jq before writing to cache; reject unexpected shapes |
| Admin key with revocable read-write access (no scoping) | Admin keys can manage org members, workspaces, and other API keys -- far more access than needed for usage monitoring | Document this risk prominently; recommend users create a dedicated org with limited blast radius, or lobby Anthropic for read-only admin keys |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing raw numbers (tokens, cents) without context | Users can't tell if "45,231 tokens used" is a lot or a little | Show percentage bars with labels: "Spend: 23% of $500/mo" |
| Not showing data freshness | Users don't know if the display is current or 30 minutes stale | Show "Updated 3m ago" timestamp; dim or flag stale data (>15 min old) |
| Cramming all stats into one status segment | Unreadable wall of tiny text in status bar | Default to 1-2 key metrics; let users configure which segments appear |
| No visual indication of errors or missing data | Users see empty status bar and don't know why | Show "Claudux: No key" or "Claudux: Err" with color coding (red) |
| Progress bars without labels | "What does this bar even mean?" | Prefix each bar: `S:` for Sonnet, `$:` for spend, etc. |
| Ignoring narrow terminal widths | Status bar content wraps or disappears on small terminals | Implement responsive formatting: fewer details at narrower widths |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **API integration:** Works with Admin key but fails silently with standard key -- verify key type detection and error messaging
- [ ] **Cache system:** Writes work but concurrent reads during writes return partial JSON -- verify atomic write pattern (write to tmpfile + `mv`)
- [ ] **Progress bars:** Look correct on your terminal but garble on others -- verify on iTerm2, GNOME Terminal, Alacritty, and plain `xterm`
- [ ] **Plugin installation:** Works with TPM `prefix + I` but manual git clone install path is broken -- verify both installation methods
- [ ] **macOS compatibility:** Works on Linux but `curl`, `date`, `jq` behave differently on macOS -- verify with macOS Homebrew and system tools (macOS `date` does not support `--date`, use `date -j` instead)
- [ ] **Multiple tmux sessions:** Works with one session but background fetcher conflicts with multiple sessions -- verify with 3+ concurrent sessions
- [ ] **Empty state:** Shows garbage when API has never been called (no usage data exists) -- verify graceful empty state display
- [ ] **Key rotation:** Works with current key but does not pick up a new key without killing tmux server -- verify hot-reload of key changes
- [ ] **Spend limit display:** Shows current spend but does not show what tier the user is on or what the limit is -- need both numerator and denominator for the progress bar

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong API key type used throughout | MEDIUM | Refactor data layer to accept Admin key; add key-type detection; update all docs; provide fallback mode using rate-limit headers for users without Admin access |
| Synchronous API calls in status bar | HIGH | Requires full architectural rewrite to daemon + cache pattern; must redesign data flow |
| API key leaked in git history | HIGH | Revoke key immediately via Claude Console; `git filter-branch` or BFG Repo Cleaner to scrub history; force push; notify affected org members |
| Unicode rendering broken across terminals | LOW | Replace Unicode chars with ASCII fallback; add `@claudux-ascii-mode` option |
| Cache race conditions corrupting display | LOW | Implement atomic writes (`mv` pattern); add JSON validation before display |
| Background fetcher spawning duplicates | LOW | Add PID file locking with `flock`; add cleanup on plugin init |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Wrong quota concept (API vs subscription) | Phase 0: Requirements | Clear spec document defining exactly which quotas are tracked |
| Admin API key requirement | Phase 1: Core API Integration | Integration test with both Admin and standard keys; graceful error for wrong type |
| Blocking API calls in status bar | Phase 1: Architecture | Load test with `status-interval 1` and simulated 5s API latency; no cursor stutter |
| API key security | Phase 1: Configuration | Security audit checklist; `ps aux` test showing no key exposure |
| Unicode rendering issues | Phase 2: Display | Screenshot comparison across 4+ terminal emulators |
| Cache race conditions | Phase 2: Reliability | Stress test with rapid `tmux source ~/.tmux.conf` while fetcher runs |
| Multiple session conflicts | Phase 2: Reliability | Test with 5 concurrent tmux sessions |
| macOS/Linux portability | Phase 3: Distribution | CI test matrix on Ubuntu and macOS runners |
| TPM packaging conventions | Phase 3: Distribution | Verified install via `prefix + I` and manual `git clone` |
| Empty states and error display | Phase 2: UX Polish | Manual test of every error path: no key, expired key, no data, API down |

## Sources

- [Anthropic Rate Limits Documentation](https://platform.claude.com/docs/en/api/rate-limits) -- HIGH confidence (official docs)
- [Anthropic Usage and Cost API Documentation](https://platform.claude.com/docs/en/api/usage-cost-api) -- HIGH confidence (official docs, confirms Admin key requirement)
- [Anthropic API Key Best Practices](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure) -- HIGH confidence (official help center)
- [tmux Issue #3352: Subshell performance with large scrollback](https://github.com/tmux/tmux/issues/3352) -- HIGH confidence (official tmux repo, confirmed by maintainer)
- [tmux Issue #632: Unicode character width confusion](https://github.com/tmux/tmux/issues/632) -- HIGH confidence (official tmux repo)
- [tmux Issue #3865: Unicode not displaying correctly](https://github.com/tmux/tmux/issues/3865) -- HIGH confidence (official tmux repo)
- [tmux Issue #2050: Status bar shell commands being disowned](https://github.com/tmux/tmux/issues/2050) -- HIGH confidence (official tmux repo)
- [TPM Plugin Creation Guide](https://github.com/tmux-plugins/tpm/blob/master/docs/how_to_create_plugin.md) -- HIGH confidence (official TPM docs)
- [Claude Pro/Max Weekly Rate Limits](https://hypereal.tech/a/weekly-rate-limits-claude-pro-max-guide) -- LOW confidence (third-party source, no official API endpoint confirmed)
- [Optimizing tmux 3.4 Status Bar for DevOps Metrics](https://blogdeveloperspot.blogspot.com/2025/06/crafting-your-perfect-tmux-status-bar.html) -- MEDIUM confidence (community source, aligned with official tmux behavior)
- [Anthropic Admin API Overview](https://docs.anthropic.com/en/docs/administration/administration-api) -- HIGH confidence (official docs)

---
*Pitfalls research for: tmux status bar plugin / Claude API monitoring*
*Researched: 2026-03-10*
