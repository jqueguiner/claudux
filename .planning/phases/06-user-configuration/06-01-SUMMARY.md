---
phase: 06-user-configuration
plan: 01
subsystem: config
tags: [tmux, bash, toggle, dispatcher]

requires:
  - phase: 05-plugin-integration
    provides: "Dispatcher routing and format string registration"
provides:
  - "Show/hide toggle guards for all display segments"
  - "Bar length clamping in render_bar (5-30 range)"
affects: [06-user-configuration, 07-documentation-distribution]

tech-stack:
  added: []
  patterns: ["Toggle guard pattern: check get_tmux_option before render call"]

key-files:
  created: []
  modified: [scripts/claudux.sh, scripts/render.sh]

key-decisions:
  - "Toggle checks in dispatcher, not in individual render functions — single point of control"
  - "Status segment (error/stale) has no toggle — always visible for operational health"
  - "Bar length clamped to 5-30 with 2>/dev/null for non-integer safety"

patterns-established:
  - "Toggle guard: [[ \"$(get_tmux_option @claudux_show_X $DEFAULT)\" == \"on\" ]] && render_X"

requirements-completed: [CONF-01, CONF-05]

duration: 3min
completed: 2026-03-10
---

# Phase 6 Plan 01: User Configuration - Toggle Guards & Bar Clamping Summary

**Show/hide toggle guards for all 6 display segments in dispatcher, bar_length clamping (5-30) in render_bar**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-10
- **Completed:** 2026-03-10
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- All 6 display segments (weekly, monthly, sonnet, opus, reset, email) now check @claudux_show_* option before rendering
- Sonnet and opus share single @claudux_show_model toggle
- Status segment (error/stale indicators) always renders — no toggle
- render_bar() clamps bar_length to 5-30 range with non-integer safety

## Task Commits

1. **Task 1: Add toggle guards to dispatcher** + **Task 2: Bar length clamping** - `240ae75` (feat)

## Files Created/Modified
- `scripts/claudux.sh` - Added toggle guard before each render call in case statement
- `scripts/render.sh` - Added bar_length clamping (5-30) in render_bar()

## Decisions Made
- Toggle checks placed in dispatcher, not render functions — keeps render functions as pure renderers
- Status segment exempted from toggles — error/stale indicators are operational health signals

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Toggle guards ready for end-to-end testing in Plan 06-02
- All config options now have functional code paths

---
*Phase: 06-user-configuration*
*Completed: 2026-03-10*
