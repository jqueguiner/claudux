# Claudux

## What This Is

A tmux status bar plugin that displays real-time Claude API usage statistics. Shows consumption quotas (weekly, monthly), model-specific usage as progress bars, reset dates with times, and the associated account email — all rendered in the bottom tmux panel.

## Core Value

At a glance, developers using Claude know exactly where they stand on quota usage without leaving their terminal.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Display weekly consumption quota as a progress bar
- [ ] Display monthly consumption quota as a progress bar
- [ ] Show Sonnet-specific usage as a dedicated progress bar
- [ ] Show quota reset dates with associated hour/time
- [ ] Display the account email associated with the API key
- [ ] Render all stats in the tmux status bar (bottom panel)
- [ ] Auto-refresh stats at a reasonable interval
- [ ] Clean, readable formatting that fits standard tmux status lines
- [ ] Modular architecture suitable for open-source distribution
- [ ] Configuration file for customizing display (which stats, colors, format)

### Out of Scope

- GUI/web dashboard — this is terminal-only
- Historical usage tracking/graphing — just current period stats
- Billing management or payment actions — read-only display
- Support for non-Claude AI providers — Claude-focused tool

## Context

- Target users: developers who use Claude API/Claude Code heavily and want quota visibility
- Environment: tmux on Linux/macOS terminals
- The Anthropic API provides usage/billing endpoints that expose quota data
- tmux supports custom status bar segments via shell scripts or plugins (TPM ecosystem)
- Progress bars in terminal can be rendered with Unicode block characters (▓░) or similar

## Constraints

- **Runtime**: Must be lightweight — tmux status bar refreshes frequently, so the script must be fast and cache responses
- **Dependencies**: Minimal — shell/Python/Node script, no heavy frameworks
- **Compatibility**: tmux 3.0+ on Linux and macOS
- **Auth**: Needs Anthropic API key (via env var or config file)
- **Design philosophy**: Pragmatic, clear, modular, maintainable — designed to scale as a real open-source tool

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| tmux status bar (not separate pane) | Less intrusive, always visible, standard pattern for tmux plugins | — Pending |
| Progress bar visualization for quotas | Intuitive at-a-glance reading vs raw numbers | — Pending |
| Cache API responses | Avoid rate limits and keep status bar refresh fast | — Pending |

---
*Last updated: 2026-03-10 after initialization*
