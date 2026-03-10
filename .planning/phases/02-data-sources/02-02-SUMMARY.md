---
plan: 02-02
phase: 02-data-sources
status: complete
started: 2026-03-10
completed: 2026-03-10
duration: ~5 min
---

# Plan 02-02 Summary: JSONL Log Parser

## What Was Built
Created `scripts/local_parse.sh` -- a Claude Code JSONL session log parser that aggregates token usage by time window (7d weekly, 30d monthly) and model family. Outputs normalized JSON matching the shared cache schema.

## Key Decisions
- Used single-jq-pass per file for performance (not per-line jq)
- Used temp files for accumulation across subshell boundaries (pipeline subshell issue)
- Plan limits hardcoded as approximate values with documentation
- JSONL path uses `~/.claude/projects/*/*.jsonl` (verified actual path, not the `*/sessions/*.jsonl` from CONTEXT.md)
- Files filtered by 30-day mtime to limit scan scope
- Uses `bc` for percentage calculation with scale=1 precision
- Email lookup tries `~/.claude/settings.json`, defaults to "local"

## Self-Check: PASSED
- [x] bash -n passes (no syntax errors)
- [x] All 6 functions defined: _get_plan_limits, _get_cutoff_epoch, _normalize_model, _iso_to_epoch, _find_session_files, parse_local_logs
- [x] Filters for assistant-type entries only
- [x] Aggregates by time window and model family
- [x] Calculates percentages against plan limits
- [x] Output matches cache schema

## Key Files
<key-files>
  <created>scripts/local_parse.sh</created>
</key-files>

## Deviations
- Used temp file accumulation instead of direct variables due to Bash subshell scoping in pipelines. This is a well-known Bash limitation with `while read` inside pipelines.
