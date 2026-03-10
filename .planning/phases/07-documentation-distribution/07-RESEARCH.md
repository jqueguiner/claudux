# Phase 7: Documentation & Distribution - Research

**Researched:** 2026-03-10
**Domain:** Documentation (README.md + LICENSE) for tmux plugin distribution
**Confidence:** HIGH

## Summary

Phase 7 creates no new code. It produces two files at the project root: `README.md` and `LICENSE`. The README must enable a new user to install, configure, and use claudux from the documentation alone, covering both org (Admin API) and local (Claude Code subscription) data source modes.

The existing codebase is fully implemented through Phase 6. All configuration options, format strings, rendering functions, credential handling, and mode detection are in place. Documentation needs only to accurately describe what exists.

**Primary recommendation:** Write README.md by extracting all user-facing details from the actual codebase (config/defaults.sh, claudux.tmux, scripts/credentials.sh, scripts/detect_mode.sh, scripts/check_deps.sh) rather than from memory or context docs, to ensure accuracy.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- README structure follows tmux-battery pattern: name, screenshot, install, config, data sources, format strings, troubleshooting, license
- Screenshot/demo is an ASCII mockup in a fenced code block (no image file for v1)
- TPM install is primary (recommended), manual git clone is secondary
- Use placeholder `user/claudux` for GitHub org
- Configuration section uses a table of all @claudux_* options with defaults
- Data sources section: org mode (Admin API key steps) and local mode (auto-detected)
- Format strings reference table with all #{claudux_*} strings
- Troubleshooting covers: nothing shows up, [!] auth_failed, stale ?, bars show 0%
- MIT License
- Keep it scannable -- headers, tables, code blocks, no walls of text

### Claude's Discretion
- Exact wording and tone of documentation
- Whether to include a "Contributing" section (keep minimal for v1)
- Badge style (if any)

### Deferred Ideas (OUT OF SCOPE)
- None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOCS-01 | README covers installation (TPM + manual), configuration options, and screenshots | Codebase provides: claudux.tmux for install patterns, config/defaults.sh for all options, render.sh for visual output reference |
| DOCS-02 | README documents Admin API key provisioning steps for org users | credentials.sh shows: env var `ANTHROPIC_ADMIN_API_KEY` or config file `~/.config/claudux/credentials` with 600 permissions; key prefix `sk-ant-admin` |
| DOCS-03 | README documents local mode setup for Claude Code subscription users | detect_mode.sh shows: auto-detected when no admin key present and `~/.claude/projects/*/sessions/*.jsonl` logs exist |
</phase_requirements>

## Standard Stack

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Markdown | README.md format | Universal standard for GitHub/open-source documentation |
| MIT License | LICENSE file | Most common open-source tmux plugin license (tmux-battery, tmux-cpu, tmux-resurrect all use MIT) |

### Supporting
No external tools needed. Documentation is plain text files.

## Architecture Patterns

### Recommended README Structure (from tmux-battery reference)
```
README.md
├── Project name + tagline
├── Screenshot/demo
├── Requirements
├── Installation
│   ├── TPM (recommended)
│   └── Manual
├── Usage (format strings + status-right example)
├── Configuration (options table)
├── Data Sources
│   ├── Org mode (Admin API)
│   └── Local mode (Claude Code)
├── Troubleshooting
├── License
└── (Optional) Contributing
```

### Pattern 1: Accurate Configuration Table
**What:** Extract all options from config/defaults.sh to ensure documentation matches code
**Source data:**

| Option | Default | Source |
|--------|---------|--------|
| `@claudux_show_weekly` | `on` | CLAUDUX_DEFAULT_SHOW_WEEKLY |
| `@claudux_show_monthly` | `on` | CLAUDUX_DEFAULT_SHOW_MONTHLY |
| `@claudux_show_model` | `on` | CLAUDUX_DEFAULT_SHOW_MODEL |
| `@claudux_show_reset` | `on` | CLAUDUX_DEFAULT_SHOW_RESET |
| `@claudux_show_email` | `off` | CLAUDUX_DEFAULT_SHOW_EMAIL |
| `@claudux_bar_length` | `10` | CLAUDUX_DEFAULT_BAR_LENGTH |
| `@claudux_warning_threshold` | `50` | CLAUDUX_DEFAULT_WARNING_THRESHOLD |
| `@claudux_critical_threshold` | `80` | CLAUDUX_DEFAULT_CRITICAL_THRESHOLD |
| `@claudux_refresh_interval` | `300` | CLAUDUX_DEFAULT_REFRESH_INTERVAL |

### Pattern 2: Accurate Format Strings Table
**What:** Extract all format strings from claudux.tmux registration array
**Source data:**

| Format String | Segment | Renders |
|--------------|---------|---------|
| `#{claudux_weekly}` | weekly | Weekly quota progress bar |
| `#{claudux_monthly}` | monthly | Monthly quota progress bar |
| `#{claudux_sonnet}` | sonnet | Sonnet model usage bar |
| `#{claudux_opus}` | opus | Opus model usage bar |
| `#{claudux_reset}` | reset | Reset countdown |
| `#{claudux_email}` | email | Account email |
| `#{claudux_status}` | status | Error + stale indicators |

### Pattern 3: Credential Setup Documentation
**What:** Document the two credential paths from credentials.sh
**Source data:**
1. Environment variable: `export ANTHROPIC_ADMIN_API_KEY=sk-ant-admin...`
2. Config file: `~/.config/claudux/credentials` (must be chmod 600)
   - Contains key on first non-empty, non-comment line
   - Rejects files with permissions other than 600

### Pattern 4: Mode Detection Documentation
**What:** Document auto-detection logic from detect_mode.sh
**Source data:**
1. Forced: `@claudux_mode` tmux option (org/local/auto)
2. Auto: Admin API key with `sk-ant-admin` prefix detected -> org mode
3. Auto: `~/.claude/projects/*/sessions/*.jsonl` exists -> local mode
4. Fallback: "none" with return code 1

### Pattern 5: Dependencies Documentation
**What:** Document requirements from check_deps.sh
**Source data:**
- Bash 4.0+ (macOS ships Bash 3.x; needs `brew install bash`)
- jq (JSON processor)
- curl (HTTP client)
- tmux 3.0+ (format string interpolation support)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| License text | Write custom license | MIT License template | Standard, legally vetted |
| ASCII mockup | Generate from code | Hand-craft in README | Static mockup is simpler and works in any context |

## Common Pitfalls

### Pitfall 1: Documentation Drift from Code
**What goes wrong:** README documents options/features that don't exist or misses ones that do
**Why it happens:** Writing docs from memory instead of reading actual source files
**How to avoid:** Extract every option, format string, and credential path directly from source files
**Warning signs:** Option names in README don't match config/defaults.sh variable names

### Pitfall 2: Incomplete Credential Instructions
**What goes wrong:** Users can't find where to get an Admin API key
**Why it happens:** Docs say "set your API key" without explaining HOW to get one
**How to avoid:** Include step-by-step: Console -> Organization Settings -> Admin API keys -> Create key with appropriate permissions
**Warning signs:** "Where do I get my API key?" support requests

### Pitfall 3: macOS Bash Version
**What goes wrong:** macOS users get errors because default Bash is 3.x
**Why it happens:** Apple ships ancient Bash due to GPLv3 licensing
**How to avoid:** Prominently document Bash 4.0+ requirement with `brew install bash` fix
**Warning signs:** Syntax errors in array handling on macOS

### Pitfall 4: Missing tmux source Step
**What goes wrong:** Users install plugin but nothing appears
**Why it happens:** Forgot to run `tmux source ~/.tmux.conf` or `prefix + I` (TPM)
**How to avoid:** Include reload step in BOTH install methods
**Warning signs:** "Nothing shows up" troubleshooting queries

## Code Examples

### ASCII Mockup Example
Based on actual render.sh output patterns:
```
 W: [██████░░░░] 60%  S: [███░░░░░░░] 30%  O: [█░░░░░░░░░] 12%  R: 2h 15m
```

Labels from render.sh: W: (weekly), M: (monthly), S: (sonnet), O: (opus), R: (reset)
Bar characters: filled=`█`, empty=`░`, brackets=`[]`

### Example tmux.conf Configuration
```bash
# ~/.tmux.conf

# Install via TPM
set -g @plugin 'user/claudux'

# Customize display
set -g @claudux_show_weekly on
set -g @claudux_show_monthly off
set -g @claudux_bar_length 15
set -g @claudux_warning_threshold 60
set -g @claudux_critical_threshold 85

# Place in status bar
set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset}'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Real screenshots | ASCII mockups | v1 decision | Works in any context, no image hosting needed |
| Single install method | TPM + manual | Standard practice | Covers both TPM users and non-TPM users |

## Open Questions

1. **GitHub org/username for install URLs**
   - What we know: Using placeholder `user/claudux`
   - What's unclear: Final GitHub org name
   - Recommendation: Use placeholder, easy find-and-replace later

## Sources

### Primary (HIGH confidence)
- claudux codebase: config/defaults.sh, claudux.tmux, scripts/*.sh -- direct source for all documented features
- tmux-battery plugin (reference structure) -- standard tmux plugin README pattern

### Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- documenting existing code, no external dependencies
- Architecture: HIGH -- README structure follows well-established tmux plugin conventions
- Pitfalls: HIGH -- common documentation issues are well-known

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable -- documentation of existing code)
