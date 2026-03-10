# Roadmap: Claudux

## Overview

Claudux delivers a tmux status bar plugin that shows Claude API usage at a glance. The roadmap builds from the inside out: a secure, cached foundation layer first, then data source integrations (Admin API and local logs), then rendering and display, then plugin wiring and configuration, and finally documentation for distribution. Each phase delivers a testable, standalone capability. By Phase 5 the plugin is functionally complete; Phases 6-7 make it configurable and distributable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation Infrastructure** - Cache system, security patterns, cross-platform helpers, and API key handling
- [ ] **Phase 2: Data Sources** - Admin API client, local JSONL log parser, and auto-detect mode selection
- [ ] **Phase 3: Progress Bar Rendering** - Quota progress bars with Unicode block characters and color-coded urgency
- [ ] **Phase 4: Metadata & Status Display** - Reset countdowns, account email, stale data indicator, and error states
- [ ] **Phase 5: Plugin Integration** - TPM entry point, format string registration, manual install path, and auto-refresh
- [ ] **Phase 6: User Configuration** - Tmux option toggles for display, thresholds, bar length, and refresh interval
- [ ] **Phase 7: Documentation & Distribution** - README with install/config/screenshots, Admin API docs, local mode docs

## Phase Details

### Phase 1: Foundation Infrastructure
**Goal**: The plugin has a secure, cached, cross-platform substrate that all other components build on
**Depends on**: Nothing (first phase)
**Requirements**: PLUG-05, DATA-04, DATA-05, SECR-01, SECR-02, SECR-03, CONF-04
**Success Criteria** (what must be TRUE):
  1. Cache file is written atomically (tmpfile + mv) with configurable TTL, and stale cache is detected correctly on both Linux and macOS
  2. API key is read from `$ANTHROPIC_ADMIN_API_KEY` env var or a config file with 600 permissions -- never passed as a CLI argument visible in `ps aux`
  3. A `.gitignore` ships with the plugin covering config files that could contain credentials
  4. Helper functions correctly detect the platform (GNU vs BSD) and use the appropriate `stat`/`date` variants
  5. The status bar display script reads only from the cache file and never makes synchronous network calls
**Plans**: TBD

Plans:
- [ ] 01-01: TBD
- [ ] 01-02: TBD

### Phase 2: Data Sources
**Goal**: The plugin can fetch and normalize quota data from both the Anthropic Admin API (org users) and local Claude Code session logs (subscription users)
**Depends on**: Phase 1
**Requirements**: DATA-01, DATA-02, DATA-03
**Success Criteria** (what must be TRUE):
  1. Running the API fetch script with a valid Admin API key populates the cache file with usage data from Anthropic's usage report endpoint
  2. Running the local log parser with Claude Code session logs at `~/.claude/projects/*/sessions/*.jsonl` populates the cache file with parsed usage data
  3. The plugin auto-detects which data source to use based on available credentials (Admin API key present = org mode, absent = local mode) and logs the detected mode
**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: Progress Bar Rendering
**Goal**: Users see their quota consumption as color-coded progress bars in the terminal
**Depends on**: Phase 2
**Requirements**: DISP-01, DISP-02, DISP-03, DISP-04, DISP-07
**Success Criteria** (what must be TRUE):
  1. User sees a weekly consumption quota rendered as a Unicode progress bar with percentage
  2. User sees a monthly consumption quota rendered as a Unicode progress bar with percentage
  3. User sees Sonnet-specific usage as a separate labeled progress bar
  4. User sees Opus-specific usage as a separate labeled progress bar
  5. Progress bars change color based on usage level: green below 50%, yellow between 50-80%, red above 80%
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Metadata & Status Display
**Goal**: Users see contextual information beyond progress bars -- when quotas reset, which account is active, and whether the displayed data is trustworthy
**Depends on**: Phase 3
**Requirements**: DISP-05, DISP-06, DISP-08, DISP-09
**Success Criteria** (what must be TRUE):
  1. User sees quota reset dates in relative format ("resets in Xh Ym") next to or near the relevant progress bars
  2. User sees the account email associated with their API key or subscription displayed in the status bar
  3. When cached data is older than 2x the refresh interval, user sees a visual staleness indicator (dimmed color or `?` suffix)
  4. When API authentication fails or data is unavailable, user sees a clear error indicator (e.g., `[!]`) instead of blank or stale data
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Plugin Integration
**Goal**: The plugin installs and runs as a standard tmux plugin, with format strings users can place freely in their status bar
**Depends on**: Phase 4
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04
**Success Criteria** (what must be TRUE):
  1. User can install via TPM (`set -g @plugin 'user/claudux'` then `prefix + I`) and see claudux output in their status bar after sourcing tmux.conf
  2. User can install via manual git clone to `~/.tmux/plugins/claudux` and activate by adding `run-shell` to tmux.conf
  3. User can place `#{claudux_*}` format strings anywhere in `status-left` or `status-right` and they render the corresponding data segment
  4. Data auto-refreshes on a configurable interval (default 5 minutes) without user intervention, using background cache refresh
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

### Phase 6: User Configuration
**Goal**: Users can customize which stats are shown, how they look, and how often they refresh -- all via standard tmux options
**Depends on**: Phase 5
**Requirements**: CONF-01, CONF-02, CONF-03, CONF-05
**Success Criteria** (what must be TRUE):
  1. User can toggle individual stats on/off via `@claudux_show_*` tmux options (e.g., `set -g @claudux_show_weekly on`)
  2. User can customize warning (yellow) and critical (red) color thresholds via `@claudux_warning_threshold` and `@claudux_critical_threshold`
  3. User can set cache refresh interval via `@claudux_refresh_interval` and observe the change in refresh frequency
  4. User can control progress bar length via `@claudux_bar_length` and see bars render at the specified width
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

### Phase 7: Documentation & Distribution
**Goal**: A new user can discover, install, configure, and use claudux from the README alone, regardless of whether they are an org API user or a Claude Code subscription user
**Depends on**: Phase 6
**Requirements**: DOCS-01, DOCS-02, DOCS-03
**Success Criteria** (what must be TRUE):
  1. README covers both installation methods (TPM and manual git clone) with copy-pasteable commands and includes at least one screenshot showing the plugin in action
  2. README documents Admin API key provisioning steps (where to get an Admin key, how to set the env var, what permissions are needed) for org users
  3. README documents local mode setup for Claude Code subscription users (what is auto-detected, where logs are read from, any prerequisites)
**Plans**: TBD

Plans:
- [ ] 07-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation Infrastructure | 0/? | Not started | - |
| 2. Data Sources | 0/? | Not started | - |
| 3. Progress Bar Rendering | 0/? | Not started | - |
| 4. Metadata & Status Display | 0/? | Not started | - |
| 5. Plugin Integration | 0/? | Not started | - |
| 6. User Configuration | 0/? | Not started | - |
| 7. Documentation & Distribution | 0/? | Not started | - |
