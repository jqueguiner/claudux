# claudux

Claude API quota usage monitor for your tmux status bar.

See your Claude usage at a glance — weekly/monthly quotas, per-model breakdown, cost tracking, token velocity, system vitals, and reset countdowns — right in your tmux status bar.

```
 Weekly: [██████░░░░] 60%  Sonnet: [████░░░░░░] 42%  Opus: [███░░░░░░░] 30%  Cost Weekly: ~$12.50  Velocity: 45.2k/h ^  Reset Weekly: 2h 15m  ● opus
```

## Features

### Quota Monitoring
- **Weekly & Monthly usage bars** — Color-coded progress bars (green / yellow / red) with configurable thresholds
- **Per-model breakdown** — Separate usage bars for Sonnet and Opus models
- **Reset countdowns** — Time until weekly and monthly quota resets (adaptive format: `2d 5h`, `3h 12m`, `47m`)

### Cost & Analytics
- **Cost tracking** — Weekly and monthly spend in dollars (estimated in local mode)
- **Token velocity** — Tokens per hour with trend arrows (^ up, v down, - stable)
- **Daily burn rate** — Projects when you'll hit your rate limit (`~3h left`, `depleted`)
- **Rate limit predictor** — Warns when approaching limits (`Rate Limit: ~2h` when >70% used)

### Live Session Monitoring
- **Context window usage** — Percentage of the 200k context window used in the active session
- **Model indicator** — Colored dot showing the last model used (purple for Opus, blue for Sonnet, orange for Haiku)
- **Cooldown timer** — Countdown when rate-limited, with reset info from session logs
- **Token heartbeat** — Pulsing dot that changes color based on API activity recency (green < 5s, yellow < 15s, dim > 15s)
- **Parallel session count** — Number of running Claude processes with memory usage in MB
- **Rate limit history** — Rate limit frequency over 1h/24h/7d windows

### System Vitals
- **Workspace vitals** — CPU, memory, and disk usage as sparkline bars with color-coded severity

### Profile System
- **Multiple profiles** — Manage separate Claude accounts/subscriptions side by side
- **Auto-profile switching** — Detects `CLAUDE_CONFIG_DIR` per tmux pane and switches automatically
- **Interactive profile selector** — `Ctrl+B R` to rotate, `Ctrl+B Shift+R` for popup menu
- **Per-profile cache isolation** — Each profile maintains its own cache and data

### Plan Detection
- **Automatic plan detection** — Reads subscription type (Free, Pro, Max, Team, Enterprise) from local credentials or API
- **Plan-aware limits** — Quota bars automatically scale to your plan's token limits

### Label Modes
- **Verbose / Compact labels** — Toggle between full labels (`Weekly`, `Sonnet`) and compact (`W`, `S`) with `Ctrl+B T`

### Help & Discoverability
- **Built-in help popup** — `Ctrl+B H` opens a tmux popup with all keybindings, segments, commands, and options
- **Man page** — `man claudux` for full documentation

### Data Sources
- **Org Mode (Admin API)** — For organizations with Anthropic API Admin keys. Fetches real billing data.
- **Local Mode (Claude Code Subscribers)** — Zero-config for Pro/Max/Team/Enterprise users. Parses `~/.claude/` session logs locally. No network calls.
- **Auto-detection** — Automatically picks the right mode based on available credentials

### Error Handling
- **Stale data indicator** — Yellow `?` when cache data is older than 2x refresh interval
- **Error indicator** — Red `[!] auth_failed` (or other error codes) when something goes wrong
- **Non-blocking refresh** — Background fetches with lock files to prevent duplicate requests
- **Dependency checks** — Warns (but doesn't crash) if jq, curl, or bash 4.0+ are missing

## Requirements

- tmux 3.0+ (3.3+ for popup features)
- Bash 4.0+ (macOS ships 3.x — install with `brew install bash`)
- [jq](https://jqlang.github.io/jq/) — `brew install jq` / `sudo apt install jq`
- [curl](https://curl.se/) — `brew install curl` / `sudo apt install curl`

## Installation

### One-line Install

```bash
curl -fsSL https://raw.githubusercontent.com/jqueguiner/claudux/master/install.sh | bash
```

This single command will:

1. **Install dependencies** — Homebrew (if missing) + `bash 4.0+`, `jq`, `curl`, `tmux` on macOS; `apt-get` on Linux
2. **Clone claudux** to `~/.tmux/plugins/claudux` (or pull latest if already installed)
3. **Add `run-shell`** to your `~/.tmux.conf` (skips if already present)
4. **Symlink `claudux-setup`** to `~/.local/bin` for easy CLI access
5. **Reload tmux** automatically if a session is running

### Homebrew

```bash
brew install jqueguiner/claudux/claudux
```

That's it. Homebrew installs all dependencies (`bash 4.0+`, `jq`, `curl`, `tmux`), adds claudux to your `~/.tmux.conf`, and reloads tmux automatically.

### TPM (Tmux Plugin Manager)

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'jqueguiner/claudux'
```

Reload and install:

```bash
tmux source ~/.tmux.conf
# Press: prefix + I
```

### Manual

```bash
git clone https://github.com/jqueguiner/claudux ~/.tmux/plugins/claudux
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claudux/claudux.tmux
```

Reload:

```bash
tmux source ~/.tmux.conf
```

## Usage

Claudux auto-injects default segments into your status bar on load. To customize, add format strings to your `status-right` (or `status-left`) in `~/.tmux.conf`:

```bash
set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset}'
```

Reload with `tmux source ~/.tmux.conf`.

## Format Strings

| Format String | Description |
|---|---|
| `#{claudux_weekly}` | Weekly quota progress bar |
| `#{claudux_monthly}` | Monthly quota progress bar |
| `#{claudux_sonnet}` | Sonnet model usage bar |
| `#{claudux_opus}` | Opus model usage bar |
| `#{claudux_reset}` | Reset countdown (weekly + monthly) |
| `#{claudux_cost}` | Cost tracking (weekly + monthly in $) |
| `#{claudux_velocity}` | Token velocity (tokens/h + trend arrow) |
| `#{claudux_context}` | Context window usage bar (% of 200k) |
| `#{claudux_model}` | Model indicator (colored dot + name) |
| `#{claudux_burn}` | Burn rate / time-to-limit estimate |
| `#{claudux_cooldown}` | Rate limit cooldown timer |
| `#{claudux_sessions}` | Active Claude session count + memory |
| `#{claudux_heartbeat}` | Activity heartbeat dot |
| `#{claudux_ratelimits}` | Rate limit history (1h/24h/7d) |
| `#{claudux_predictor}` | Rate limit prediction warning |
| `#{claudux_vitals}` | System vitals (CPU/mem/disk sparklines) |
| `#{claudux_profile}` | Active profile name |
| `#{claudux_email}` | Account email |
| `#{claudux_status}` | Error / stale indicator |

## Keybindings

| Key | Action |
|---|---|
| `Ctrl+B R` | Rotate to next profile |
| `Ctrl+B Shift+R` | Open profile selector popup |
| `Ctrl+B T` | Toggle verbose/compact labels |
| `Ctrl+B H` | Show help popup |

All keybindings are configurable via tmux options (`@claudux_rotate_key`, `@claudux_label_key`, `@claudux_help_key`).

## Configuration

All options are set via tmux options in `~/.tmux.conf`:

| Option | Default | Description |
|---|---|---|
| `@claudux_show_weekly` | `on` | Show weekly quota bar |
| `@claudux_show_monthly` | `on` | Show monthly quota bar |
| `@claudux_show_model` | `on` | Show Sonnet/Opus bars |
| `@claudux_show_reset` | `on` | Show reset countdown |
| `@claudux_show_email` | `off` | Show account email |
| `@claudux_show_cost` | `on` | Show cost tracking |
| `@claudux_show_velocity` | `on` | Show token velocity |
| `@claudux_show_context` | `on` | Show context window usage |
| `@claudux_show_model_indicator` | `on` | Show model indicator dot |
| `@claudux_show_burn` | `on` | Show burn rate |
| `@claudux_show_sessions` | `on` | Show session count |
| `@claudux_show_rate_limits` | `on` | Show rate limit history |
| `@claudux_show_predictor` | `on` | Show rate limit predictor |
| `@claudux_show_vitals` | `on` | Show system vitals |
| `@claudux_bar_length` | `10` | Progress bar width (3-30) |
| `@claudux_warning_threshold` | `50` | Yellow threshold (%) |
| `@claudux_critical_threshold` | `80` | Red threshold (%) |
| `@claudux_refresh_interval` | `300` | Cache TTL in seconds |
| `@claudux_label_mode` | `verbose` | Label style: `verbose` or `compact` |
| `@claudux_auto_profile` | `off` | Auto-switch profile per pane |
| `@claudux_mode` | `auto` | Force data source: `auto`, `org`, or `local` |

### Example

```bash
# ~/.tmux.conf

# Wider bars, tighter thresholds
set -g @claudux_bar_length 15
set -g @claudux_warning_threshold 40
set -g @claudux_critical_threshold 75

# Compact labels, auto-profile
set -g @claudux_label_mode compact
set -g @claudux_auto_profile on

# Show email, hide monthly
set -g @claudux_show_email on
set -g @claudux_show_monthly off

# Refresh every 10 minutes
set -g @claudux_refresh_interval 600

# Status bar layout
set -g status-right '#{claudux_profile} #{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_cost} #{claudux_velocity} #{claudux_reset} #{claudux_status}'
```

## CLI Tool

`claudux-setup` manages installation and profiles:

```
claudux-setup install              Add claudux to ~/.tmux.conf
claudux-setup uninstall            Remove claudux from ~/.tmux.conf
claudux-setup status               Show installation status and dependencies
claudux-setup profile list         List all profiles (* = active)
claudux-setup profile add <name>   Add a profile (interactive login)
  --mode local|org                 Data source mode
  --key API_KEY                    Anthropic Admin API key (org mode)
  --dir CLAUDE_DIR                 Claude config directory (local mode)
  --no-login                       Skip interactive Claude login
claudux-setup profile delete <name>
claudux-setup profile switch <name>
claudux-setup profile next         Rotate to next profile
claudux-setup help                 Show help
```

## Data Sources

### Org Mode (Admin API)

For organizations using the Anthropic API with an Admin API key.

1. Go to [Anthropic Console](https://console.anthropic.com/) > **Organization Settings** > **Admin API keys**
2. Create a new Admin API key (requires admin permissions) — starts with `sk-ant-admin`
3. Set the key:

```bash
export ANTHROPIC_ADMIN_API_KEY=sk-ant-admin01-your-key-here
```

Or via config file:

```bash
mkdir -p ~/.config/claudux
echo "sk-ant-admin01-your-key-here" > ~/.config/claudux/credentials
chmod 600 ~/.config/claudux/credentials
```

The config file **must** have `600` permissions (owner read/write only).

### Local Mode (Claude Code Subscribers)

For Pro, Max, Team, and Enterprise subscribers. No API key needed.

- Auto-detected when `~/.claude/projects/` contains JSONL session logs
- Reads local Claude Code session logs at `~/.claude/projects/*/sessions/*.jsonl`
- No network calls required
- Subscription plan auto-detected from local credentials for accurate quota limits

## Troubleshooting

**Nothing shows up**

1. Reload tmux config: `tmux source ~/.tmux.conf`
2. Check dependencies: `which jq curl bash`
3. Verify Bash version: `bash --version` (need 4.0+)
4. Check format strings are in your `status-right` or `status-left`

**Shows `[!] auth_failed`**

- Verify your Admin API key starts with `sk-ant-admin`
- Check the key hasn't been revoked
- If using a config file, verify permissions: `ls -la ~/.config/claudux/credentials` (should be `-rw-------`)

**Shows stale `?`**

- Check internet connectivity (org mode requires API access)
- Try increasing the refresh interval: `set -g @claudux_refresh_interval 600`

**Bars show 0%**

- In local mode: verify `~/.claude/projects/` exists and contains `.jsonl` session files
- In org mode: verify your organization has usage data for the current billing period
- Try running `~/.tmux/plugins/claudux/scripts/fetch.sh` manually to see error output

## Uninstall

```bash
claudux-setup uninstall
tmux source-file ~/.tmux.conf
```

Or if installed via Homebrew:

```bash
brew uninstall claudux
```

## License

MIT License — see [LICENSE](LICENSE).
