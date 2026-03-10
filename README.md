# claudux

Claude API quota usage monitor for tmux.

See your Claude usage at a glance -- weekly/monthly quotas, per-model breakdown, and reset countdowns -- right in your tmux status bar.

```
 W: [██████░░░░] 60%  M: [████░░░░░░] 42%  S: [███░░░░░░░] 30%  O: [█░░░░░░░░░] 12%  R: 2h 15m
```

## Requirements

- tmux 3.0+
- Bash 4.0+ (macOS ships 3.x -- install with `brew install bash`)
- [jq](https://jqlang.github.io/jq/) -- `brew install jq` / `sudo apt install jq`
- [curl](https://curl.se/) -- `brew install curl` / `sudo apt install curl`

## Installation

### TPM (recommended)

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'user/claudux'
```

Then reload and install:

```bash
# Reload config
tmux source ~/.tmux.conf

# Install plugins
# Press: prefix + I
```

### Manual

```bash
git clone https://github.com/user/claudux ~/.tmux/plugins/claudux
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

Add format strings to your `status-right` (or `status-left`) in `~/.tmux.conf`:

```bash
set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset}'
```

Reload with `tmux source ~/.tmux.conf` to see your quota usage.

## Format Strings

| Format String | Renders |
|---------------|---------|
| `#{claudux_weekly}` | Weekly quota progress bar |
| `#{claudux_monthly}` | Monthly quota progress bar |
| `#{claudux_sonnet}` | Sonnet model usage bar |
| `#{claudux_opus}` | Opus model usage bar |
| `#{claudux_reset}` | Reset countdown (e.g., `2h 15m`) |
| `#{claudux_email}` | Account email |
| `#{claudux_status}` | Error/stale indicator |

## Configuration

All options are set via tmux options in `~/.tmux.conf`:

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
| `@claudux_refresh_interval` | `300` | Cache TTL in seconds |

### Example

```bash
# ~/.tmux.conf

# Wider bars, tighter thresholds
set -g @claudux_bar_length 15
set -g @claudux_warning_threshold 40
set -g @claudux_critical_threshold 75

# Show email, hide monthly
set -g @claudux_show_email on
set -g @claudux_show_monthly off

# Refresh every 10 minutes
set -g @claudux_refresh_interval 600

# Status bar layout
set -g status-right '#{claudux_weekly} #{claudux_sonnet} #{claudux_opus} #{claudux_reset} #{claudux_email}'
```

## Data Sources

Claudux supports two data source modes, auto-detected based on available credentials.

### Org Mode (Admin API)

For organizations using the Anthropic API with an Admin API key.

**Setup:**

1. Go to the [Anthropic Console](https://console.anthropic.com/)
2. Navigate to **Organization Settings** > **Admin API keys**
3. Create a new Admin API key (requires admin permissions)
4. The key starts with `sk-ant-admin`

Set the key via environment variable (recommended):

```bash
export ANTHROPIC_ADMIN_API_KEY=sk-ant-admin01-your-key-here
```

Or via config file:

```bash
mkdir -p ~/.config/claudux
echo "sk-ant-admin01-your-key-here" > ~/.config/claudux/credentials
chmod 600 ~/.config/claudux/credentials
```

The config file **must** have `600` permissions (owner read/write only). Claudux will refuse to read it otherwise.

**What you see:** Monthly spend, per-model usage breakdown, account email.

### Local Mode (Claude Code Subscribers)

For Claude Code subscription users (Pro, Max). No API key needed.

**How it works:**

- Auto-detected when no Admin API key is present and `~/.claude/projects/` contains JSONL session logs
- Reads local Claude Code session logs at `~/.claude/projects/*/sessions/*.jsonl`
- No network calls required

**What you see:** Estimated weekly/monthly usage, per-model breakdown from local session data.

**Note:** Usage estimates are based on local log parsing and may not match exact numbers on the Anthropic dashboard.

## Troubleshooting

**Nothing shows up**

1. Reload tmux config: `tmux source ~/.tmux.conf`
2. Check dependencies are installed: `which jq curl bash`
3. Verify Bash version: `bash --version` (need 4.0+)
4. Check that format strings are in your `status-right` or `status-left`

**Shows `[!] auth_failed`**

- Verify your Admin API key is correct and starts with `sk-ant-admin`
- Check the key hasn't been revoked in the Anthropic Console
- If using a config file, verify permissions: `ls -la ~/.config/claudux/credentials` (should show `-rw-------`)

**Shows stale `?`**

- Check internet connectivity (org mode requires API access)
- Try increasing the refresh interval: `set -g @claudux_refresh_interval 600`
- Check if the API endpoint is accessible: `curl -s https://api.anthropic.com/v1/organizations`

**Bars show 0%**

- In local mode: verify `~/.claude/projects/` exists and contains `.jsonl` session files
- In org mode: verify your organization has usage data for the current billing period
- Try running `~/.tmux/plugins/claudux/scripts/fetch.sh` manually to see error output

## License

MIT License -- see [LICENSE](LICENSE).
