# Requirements: Claudux

**Defined:** 2026-03-10
**Core Value:** At a glance, developers using Claude know exactly where they stand on quota usage without leaving their terminal.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Plugin Infrastructure

- [ ] **PLUG-01**: Plugin installs via TPM (`set -g @plugin 'user/claudux'` + `prefix + I`)
- [ ] **PLUG-02**: Plugin installs via manual git clone with documented steps
- [ ] **PLUG-03**: Plugin provides `#{claudux_*}` format strings users can place in status-left or status-right
- [ ] **PLUG-04**: Plugin auto-refreshes data on a configurable interval (default: 5 min cache TTL)
- [ ] **PLUG-05**: Plugin works on Linux (GNU) and macOS (BSD) with tmux 3.0+

### Data Sources

- [ ] **DATA-01**: Plugin fetches usage data from Anthropic Admin API for organization users (Admin API key)
- [ ] **DATA-02**: Plugin parses local Claude Code JSONL session logs for subscription users (no API key needed)
- [ ] **DATA-03**: Plugin auto-detects data source mode based on available credentials (org vs local)
- [ ] **DATA-04**: Plugin caches API responses to a file with TTL to avoid rate limits and status bar lag
- [ ] **DATA-05**: Plugin never makes synchronous API calls from the tmux status bar process

### Quota Display

- [ ] **DISP-01**: User sees weekly consumption quota as a progress bar in the tmux status bar
- [ ] **DISP-02**: User sees monthly consumption quota as a progress bar in the tmux status bar
- [ ] **DISP-03**: User sees Sonnet-specific usage as a dedicated progress bar
- [ ] **DISP-04**: User sees Opus-specific usage as a dedicated progress bar
- [ ] **DISP-05**: User sees quota reset dates with associated time (relative format: "resets in Xh Ym")
- [ ] **DISP-06**: User sees the account email associated with their API key or subscription
- [ ] **DISP-07**: Progress bars use color coding for urgency (green < 50%, yellow 50-80%, red > 80%)
- [ ] **DISP-08**: User sees a visual indicator when cached data is stale beyond expected refresh interval
- [ ] **DISP-09**: User sees a clear error indicator when API auth fails or data is unavailable

### Configuration

- [ ] **CONF-01**: User can toggle which stats are displayed via tmux options (`@claudux_show_*`)
- [ ] **CONF-02**: User can customize color thresholds via tmux options (`@claudux_warning_threshold`, `@claudux_critical_threshold`)
- [ ] **CONF-03**: User can set cache refresh interval via tmux option (`@claudux_refresh_interval`)
- [ ] **CONF-04**: User can configure API key via environment variable or config file (never CLI argument)
- [ ] **CONF-05**: User can set progress bar length via tmux option (`@claudux_bar_length`)

### Security

- [ ] **SECR-01**: API key is read from env var (`$ANTHROPIC_ADMIN_API_KEY`) or config file with 600 permissions
- [ ] **SECR-02**: API key is never passed as a CLI argument (not visible in `ps aux`)
- [ ] **SECR-03**: Plugin ships with .gitignore covering config files containing credentials

### Documentation

- [ ] **DOCS-01**: README covers installation (TPM + manual), configuration options, and screenshots
- [ ] **DOCS-02**: README documents Admin API key provisioning steps for org users
- [ ] **DOCS-03**: README documents local mode setup for Claude Code subscription users

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Features

- **ENH-01**: Compact single-segment mode (`W:45% O:12% S:8% [2h]`) via `#{claudux_compact}`
- **ENH-02**: Background daemon for cache refresh instead of on-demand fetching
- **ENH-03**: Claude Code statusLine hook integration for zero-API-call quota data
- **ENH-04**: Subscription plan auto-detection (Free/Pro/Max 5x/Max 20x)
- **ENH-05**: Spend tracking for API users (`$X.XX/$Y.00` format)
- **ENH-06**: ASCII-only fallback mode for terminals without Unicode support

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Historical usage graphs/charts | Terminal status bars are 1-2 lines; Console already provides charts |
| Billing management or payment actions | Security liability; read-only display only |
| Non-Claude AI providers | Scope creep; each provider has different APIs/auth/quotas |
| Web dashboard or GUI | Value prop is terminal-native, zero-context-switch monitoring |
| Session management or Claude Code orchestration | Other tools (claude-tmux, Codeman) do this; Claudux is monitoring only |
| AI-powered usage predictions | Adds Python/numpy dependency; questionable accuracy with changing limits |
| Desktop notifications/alerts | Platform-specific complexity; color coding provides urgency signaling |
| Token-level request logging | Privacy concern; heavy I/O; ccusage already does this |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| — | — | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 0
- Unmapped: 26 ⚠️

---
*Requirements defined: 2026-03-10*
*Last updated: 2026-03-10 after initial definition*
