---
phase: 04-metadata-status-display
plan: 01
subsystem: ui
tags: [bash, tmux, render, reset-countdown, email-display]

requires:
  - phase: 03-progress-bar-rendering
    provides: "render.sh with render_bar, render_weekly, render_monthly, render_model_* functions"
provides:
  - "render_reset function for quota reset countdown display"
  - "render_email function for account email display"
affects: [05-plugin-integration]

tech-stack:
  added: []
  patterns: ["render_* self-contained segment pattern extended with metadata functions"]

key-files:
  created: []
  modified: [scripts/render.sh]

key-decisions:
  - "Use integer arithmetic only for time calculations (no date command needed for relative time)"
  - "Pick nearest reset time when both weekly and monthly are available"
  - "Show minimum 1m instead of 0m when < 60 seconds remain"
  - "Truncate email at 20 chars with ... suffix (ASCII safe)"
  - "Treat 'local' email as empty (silent return)"

patterns-established:
  - "Metadata render functions: same cache_read + error check pattern, but output labels/text instead of bars"

requirements-completed: [DISP-05, DISP-06]

duration: 3min
completed: 2026-03-10
---

# Phase 4 Plan 01: Reset Countdown & Email Display Summary

**Quota reset countdown (R: Xh Ym) and account email display with truncation added to render.sh**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-10
- **Completed:** 2026-03-10
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- render_reset displays nearest quota reset in adaptive format (Xd Yh / Xh Ym / Xm)
- render_email displays account email dimmed with 20-char truncation
- Both functions handle all edge cases: missing data, errors, past timestamps, empty/local emails
- 11/11 verification tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Add render_reset function** - `b968b38` (feat)
2. **Task 2: Add render_email function** - `b968b38` (feat, same commit)
3. **Task 3: Verify with test data** - inline verification, all 11 tests passed

## Files Created/Modified
- `scripts/render.sh` - Added render_reset and render_email functions (88 lines)

## Decisions Made
- Integer-only arithmetic for relative time (epoch subtraction, no date command needed)
- Nearest-pick logic for reset time selection (weekly vs monthly)
- Minimum display of "1m" to avoid confusing "0m" output
- Email truncation at 20 chars with "..." (not Unicode ellipsis for terminal safety)

## Deviations from Plan

None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- render_reset ready but will show no output until data sources populate reset_at (currently 0)
- render_email works immediately with org mode (API fetches email)
- Phase 5 dispatcher will compose these with progress bars

---
*Phase: 04-metadata-status-display*
*Completed: 2026-03-10*
