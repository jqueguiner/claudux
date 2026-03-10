# Phase 7: Documentation & Distribution - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Write README.md and LICENSE so a new user can discover, install, configure, and use claudux from documentation alone. Cover both TPM and manual install, both org and local mode setup. No new code features — just documentation and packaging.

</domain>

<decisions>
## Implementation Decisions

### README structure
- Follow standard open-source tmux plugin README pattern (tmux-battery as reference):
  1. Project name + one-line description
  2. Screenshot/demo showing the plugin in action
  3. Installation (TPM + manual)
  4. Configuration (all @claudux_* options with defaults)
  5. Data sources (org mode vs local mode)
  6. Format strings reference
  7. Troubleshooting
  8. License
- Keep it scannable — headers, tables, code blocks, no walls of text

### Screenshot/demo
- Create an ASCII mockup of what the status bar looks like with claudux
- Show a realistic example with multiple bars: `W: [██████░░░░] 60% S: [███░░░░░░░] 30% O: [█░░░░░░░░░] 12% R: 2h 15m`
- Use a fenced code block — no actual image file needed for v1
- Can add real screenshots later when testing on actual tmux

### Installation section
- **TPM install** (primary, recommended):
  ```
  # Add to ~/.tmux.conf
  set -g @plugin 'user/claudux'
  # Then: prefix + I to install
  ```
- **Manual install**:
  ```
  git clone https://github.com/user/claudux ~/.tmux/plugins/claudux
  # Add to ~/.tmux.conf:
  run-shell ~/.tmux/plugins/claudux/claudux.tmux
  # Then: tmux source ~/.tmux.conf
  ```
- Note: use placeholder `user/claudux` — real GitHub org TBD

### Configuration section
- Table of all options with name, default, description:

| Option | Default | Description |
|--------|---------|-------------|
| `@claudux_show_weekly` | `on` | Show weekly quota bar |
| `@claudux_show_monthly` | `on` | Show monthly quota bar |
| `@claudux_show_model` | `on` | Show Sonnet/Opus bars |
| `@claudux_show_reset` | `on` | Show reset countdown |
| `@claudux_show_email` | `off` | Show account email |
| `@claudux_bar_length` | `10` | Progress bar width (5-30) |
| `@claudux_warning_threshold` | `50` | Yellow threshold (%) |
| `@claudux_critical_threshold` | `80` | Red threshold (%) |
| `@claudux_refresh_interval` | `300` | Cache TTL (seconds) |

- Example tmux.conf snippet showing common customization

### Data sources section
- **Org mode (API users):**
  - Requires Admin API key (`sk-ant-admin...`)
  - Steps: get key from Anthropic Console → Organization Settings → Admin API keys
  - Set via env var: `export ANTHROPIC_ADMIN_API_KEY=sk-ant-admin...`
  - Or config file: `~/.config/claudux/credentials` (chmod 600)
  - Shows: monthly spend, usage per model, account email
- **Local mode (Claude Code subscribers):**
  - No API key needed — reads local session logs
  - Auto-detected when no Admin key is present and `~/.claude/` exists
  - Shows: estimated weekly/monthly usage, per-model breakdown
  - Note: based on local log parsing, may not match exact Anthropic dashboard numbers

### Format strings reference
- Table of all `#{claudux_*}` format strings:

| Format String | Renders |
|--------------|---------|
| `#{claudux_weekly}` | Weekly quota bar |
| `#{claudux_monthly}` | Monthly quota bar |
| `#{claudux_sonnet}` | Sonnet usage bar |
| `#{claudux_opus}` | Opus usage bar |
| `#{claudux_reset}` | Reset countdown |
| `#{claudux_email}` | Account email |
| `#{claudux_status}` | Error/stale indicator |

- Example status-right config: `set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset}'`

### Troubleshooting section
- Common issues:
  - "Nothing shows up" → check `tmux source`, check deps (jq, curl)
  - "Shows [!] auth_failed" → verify Admin API key is correct, has admin prefix
  - "Shows stale ?" → check internet connectivity, increase refresh interval
  - "Bars show 0%" → local mode may not find session logs, check `~/.claude/` exists

### License
- MIT License — standard for open-source tmux plugins
- Create `LICENSE` file at project root

### Claude's Discretion
- Exact wording and tone of documentation
- Whether to include a "Contributing" section (keep minimal for v1)
- Badge style (if any)

</decisions>

<specifics>
## Specific Ideas

- User wants this to "realistically scale into a real open-source tool" — README should be professional quality
- Follow tmux-battery README as the gold standard for structure
- Keep troubleshooting practical — actual error messages users will see
- ASCII mockup over real screenshot — faster and works in any context

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `config/defaults.sh`: all default values — reference for configuration table
- `claudux.tmux`: format string list — reference for format strings table
- `scripts/claudux.sh`: segment routing — reference for format string → function mapping
- `.gitignore`: already exists — no changes needed

### Established Patterns
- Plugin follows TPM conventions exactly — documentation should reflect this
- Two data modes (org/local) — document both with clear setup steps
- All config via tmux options — no config files for user settings (only credentials)

### Integration Points
- README.md at project root
- LICENSE at project root
- No changes to existing code

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-documentation-distribution*
*Context gathered: 2026-03-10*
