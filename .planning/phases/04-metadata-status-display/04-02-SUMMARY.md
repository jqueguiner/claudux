---
phase: 04-metadata-status-display
plan: 02
subsystem: ui
tags: [bash, tmux, render, stale-indicator, error-display]

requires:
  - phase: 03-progress-bar-rendering
    provides: "render.sh with render_bar and progress bar functions"
provides:
  - "render_stale_indicator function for cache staleness detection"
  - "render_error function for error state display"
affects: [05-plugin-integration]

tech-stack:
  added: []
  patterns: ["Filesystem-based staleness detection using mtime vs cache JSON content"]

key-files:
  created: []
  modified: [scripts/render.sh]

key-decisions:
  - "Use filesystem mtime (not fetched_at JSON field) for staleness detection"
  - "Stale threshold is 2x refresh interval (configurable via @claudux_refresh_interval)"
  - "render_stale_indicator does NOT read cache JSON content -- only checks file mtime"
  - "render_error only shows error.code (not message) to save status bar space"

patterns-established:
  - "Filesystem metadata inspection: render_stale_indicator uses get_file_mtime instead of cache_read"

requirements-completed: [DISP-08, DISP-09]

duration: 3min
completed: 2026-03-10
---

# Phase 4 Plan 02: Stale Indicator & Error Display Summary

**Cache staleness detection (dim yellow ?) and error state indicator (red [!] error_code) added to render.sh**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-10
- **Completed:** 2026-03-10
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- render_stale_indicator detects stale cache by comparing file mtime against 2x refresh interval
- render_error reads error.code from cache and displays red [!] indicator with error code
- Both functions handle edge cases: missing cache, fresh cache, all known error codes
- All verification tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Add render_stale_indicator function** - `39398b5` (feat)
2. **Task 2: Add render_error function** - `39398b5` (feat, same commit)
3. **Task 3: Verify with test data** - inline verification, all core checks passed

## Files Created/Modified
- `scripts/render.sh` - Added render_stale_indicator and render_error functions (50 lines)

## Decisions Made
- Used filesystem mtime instead of JSON fetched_at field for staleness (more reliable)
- Stale threshold is 2 * refresh_interval (default 600s = 10 minutes)
- render_error shows only error.code (auth_failed, rate_limited, etc.) not full message

## Deviations from Plan

None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- render_stale_indicator works immediately -- any cache older than 2x refresh interval triggers
- render_error works immediately when cache contains error field
- Phase 5 dispatcher will compose these with progress bars (error check first, stale append)

---
*Phase: 04-metadata-status-display*
*Completed: 2026-03-10*
