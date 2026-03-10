# claudux — Feature Roadmap

## Done
- [x] Cost tracking segment (weekly/monthly spend in $)
- [x] Token velocity segment (tokens/h + trend arrow)
- [x] Profile auto-switch (detect CLAUDE_CONFIG_DIR per pane)

## Tier 1 — Core Monitoring
- [ ] Context window usage — Show % of 200k context used in active session
- [ ] Model indicator — Colored dot showing last model used (Opus/Sonnet)
- [ ] Daily burn rate — Project when you'll hit rate limit ("~3h left")
- [ ] Cooldown timer — Countdown when rate-limited
- [ ] Rate limit history — Track rate limit frequency per day/week
- [ ] Rate limit predictor — "At current pace, rate limit in ~47 min"
- [ ] Parallel session load — Count claude processes + memory usage
- [ ] Workspace vitals — CPU, memory, disk of Claude Code processes as sparklines
- [ ] Token heartbeat — Pulsing dot that beats faster during active API calls

## Tier 2 — Cost & Analytics
- [ ] Cost per project — Token spend breakdown by directory
- [ ] Model cost split — Visual Opus vs Sonnet cost ratio
- [ ] Cache hit rate — Prompt caching effectiveness (cache_read vs uncached)
- [ ] Response latency — Average time-to-first-token from session logs
- [ ] Weekly report — `claudux-setup report` generates usage summary
- [ ] Historical comparison — "This week vs last week" delta with arrows
- [ ] Token metabolism — How efficiently org converts tokens into shipped features
- [ ] Token time machine — Retrospective "what if Sonnet instead of Opus?" analysis

## Tier 3 — Git & Code Intelligence
- [ ] Diff stats — Lines added/removed by Claude Code today
- [ ] Git blame AI ratio — What % of codebase was written by Claude Code?
- [ ] File churn / hotspot detection — Which files Claude Code touches most
- [ ] Token ROI — Lines of code produced per 1k tokens spent
- [ ] Success rate — % of tasks completed without follow-up "fix" messages
- [ ] Commit quality score — Rate commits vs before Claude Code changes
- [ ] Code provenance chain — Full audit trail (human/sonnet/opus per line)
- [ ] Codebase drift monitor — How far code drifted from last human-only commit
- [ ] File ownership map — Visual map of Claude Code vs human file ownership
- [ ] Branch complexity score — Rate difficulty, compare to actual token spend
- [ ] Session heat signature — Visualize hot (AI-touched) vs cold codebase areas
- [ ] Code ripple analysis — Cascade of affected tests/imports after a change
- [ ] Workspace gravity — Files always edited together get gravity score

## Tier 4 — Session Management
- [ ] Session replay — `claudux-setup replay` to browse past sessions
- [ ] Session bookmarks — Tag and name sessions (`Ctrl+B M`)
- [ ] Smart session naming — Auto-name based on what was accomplished
- [ ] Session genealogy — Track parent/child subagent relationships as tree
- [ ] Session timeline — Visual timeline with gaps (`━━━╸ ╺━━━━╸ ╺━━`)
- [ ] Session ghost — Replay past session actions in dry-run mode
- [ ] Session constellation — Map related sessions, show work flow
- [ ] Session necromancy — Resurrect dead sessions from logs
- [ ] Session rescue — Detect when Claude Code is looping/stuck
- [ ] Session surgeon — `Ctrl+B X` cleanly terminate stuck session with state preservation
- [ ] Cross-session memory — Track what Claude Code learned across sessions
- [ ] Edit velocity graph — Edits per minute sparkline during sessions

## Tier 5 — Multi-Session Orchestration
- [ ] Multi-cursor sync — Keep panes' Claude Code sessions aware of each other
- [ ] Supervisor mode — Control other sessions from a master pane
- [ ] Auto-split panes — Auto-create tmux panes for subagents
- [ ] Multi-repo orchestrator — Coordinate across related repos
- [ ] Session gossip protocol — Sessions share discoveries across panes
- [ ] Conflict resolver — Alert when two sessions edit same file
- [ ] Change diplomacy — Negotiate priority when sessions collide
- [ ] Deadlock detector — Two sessions waiting on each other's locks
- [ ] Task decomposition monitor — Show subtask breakdown with progress
- [ ] Change request queue — Stack tasks, work through sequentially
- [ ] Autonomous night shift — Queue overnight tasks with token budget cap
- [ ] Session terrace — Multi-level layout: overview → detail → deep-dive

## Tier 6 — Intelligence & Auto-Config
- [ ] Claude Code version tracker — Show version, alert on updates
- [ ] Prompt library stats — Track which CLAUDE.md instructions used most
- [ ] Auto-CLAUDE.md — Generate CLAUDE.md recommendations from usage
- [ ] Smart context suggestions — Suggest files to add to CLAUDE.md
- [ ] Token waste detector — Flag sessions reading same file 3+ times
- [ ] Intelligent throttling — Auto-switch to Sonnet when Opus quota low (toggle)
- [ ] Predictive pre-fetch — Anticipate which files Claude Code will need
- [ ] Token recycling — Detect duplicate prompts, suggest reuse
- [ ] Auto-refactor suggestions — Suggest cleanup opportunities Claude missed
- [ ] Claude Code muscle memory — Track patterns, suggest aliases
- [ ] Adaptive refresh — Speed up updates during active sessions

## Tier 7 — Safety & Reliability
- [ ] File guardian — Protected files Claude Code should never edit
- [ ] Auto-checkpoint — Periodic git stash snapshots, `Ctrl+B U` to undo
- [ ] Session insurance — Auto restore points before risky operations
- [ ] Rollback button — `Ctrl+B Z` git-revert last Claude Code change
- [ ] Semantic git hooks — Pre-commit hooks verifying changes match intent
- [ ] Intent verification — Plain-English summary before applying changes
- [ ] Regression detector — Alert when previously fixed bugs reintroduced
- [ ] Codebase immune system — Learn healthy patterns, flag anomalies
- [ ] Claude Code flight recorder — Black box capturing last 10 min before crash
- [ ] Workspace sentinel — Watch for file conflicts, stale locks, orphans
- [ ] Canary deployments — Apply changes to shadow branch first, test, then merge

## Tier 8 — Reporting & Notifications
- [ ] Token budget alerts — tmux bell when threshold exceeded
- [ ] Terminal bell on completion — Toggle beep when long tasks finish
- [ ] Slack/Discord webhook — Alert on threshold crossing
- [ ] Claude Code standup — `claudux-setup standup` generates daily summary
- [ ] Post-mortem generator — Auto-generate what went wrong after failures
- [ ] Code confidence score — Rate confidence based on retries/reverts
- [ ] Usage calendar — GitHub-style contribution grid in terminal
- [ ] Voice of the codebase — Weekly digest of all Claude Code activity
- [ ] Token archaeology — `claudux-setup history <date>` shows any past day

## Tier 9 — Advanced & Experimental
- [ ] Claude Code health check — `claudux-setup doctor`
- [ ] Workspace snapshot — Save/restore tmux layout + session state
- [ ] Git worktree integration — Parallel sessions in separate worktrees
- [ ] Workspace rules engine — Auto-enforced per-project rules
- [ ] Annotation layer — Invisible comments marking Claude Code's reasoning
- [ ] Auto-documentation — Auto-generate changelog after task completion
- [ ] Session mood ring — tmux border color based on session health
- [ ] Prompt compression score — Rate prompting efficiency
- [ ] Multi-provider support — Track Claude, GPT, Gemini, Codex simultaneously
- [ ] SSH tunnel mode — Monitor remote Claude Code sessions
- [ ] Time-to-resolution — Average time from prompt to task completion
- [ ] Migration assistant — Auto-update config on breaking Claude Code releases
- [ ] Token carbon footprint — Estimate CO2 from API usage
- [ ] Export to Grafana/Prometheus — Push metrics via StatsD
- [ ] Natural language config — `claudux-setup set "warn me at 60%"`
- [ ] Session handoff — Transfer conversation between machines
- [ ] Token split by phase — Separate planning vs coding vs debugging tokens
- [ ] Claude Code keybinding cheatsheet — Project-specific shortcuts from CLAUDE.md
- [ ] Claude Code changelog — Show what changed in latest version
- [ ] Session diff viewer — `Ctrl+B V` side pane showing all file changes
