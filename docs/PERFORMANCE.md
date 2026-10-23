# Performance findings (koti-batching-2.7.1, 2026-10-22)

M = measured with xctrace, C = confirmed by reading the code, S = speculative.
Profiling build: Release with a `.perf` bundle ID and `CFFIXED_USER_HOME` pointing to
a copy of the real data (13 MB DB, 1818 cards, 29k screenshots).

## Startup (App Launch trace)
First frame at 1.43 s: process creation 284 ms, scene creation 471 ms,
`applicationDidFinishLaunching` 179 ms, first frame 192 ms.
After that, the splash video (about 3.6 s) and a fixed 1.5 s scroll delay (Lifecycle.swift:137).

1. C: The splash video plays on every launch (DayflowApp.swift:322-353, VideoLaunchView.swift:104), and the
   1.5 s timer delays scroll-to-now. Fix: skip the video when `didOnboard`, and scroll once cards are loaded.
2. M 75 ms main: `StorageManager.init` → `performIntegrityCheck` (`PRAGMA quick_check`), first
   touched from main via `MainView.daySummary`. Fix: warm `.shared` off main early, and run quick_check weekly.
3. M 48 ms main: `timelineDisplayDate` / `normalizedTimelineDate` (Support.swift:432-452) call
   `Calendar.date(bySettingHour:)` thousands of times from view bodies. Fix: a cheaper
   noon computation (startOfDay + 12h) and computing the value once per body.
4. M 53 ms main: `DayflowWindowBackground` decodes the 415 KB dark-window@2x.png.
5. M 30 ms main: `CanvasTimelineDataView.hourLabelColor` (Calendar work for each of the 24 labels).
6. M 23 ms main: the SupportChat WKWebView is created at launch (AppDelegate.swift:158). Fix: create it lazily.
7. C: Each launch runs a purge storm: screenshots read ×2, directory enumerations, a 1.1 GB timelapse size scan,
   and llm_calls truncation UPDATEs (StorageManager+Maintenance.swift:329-545). Fix: delay 60 s plus done flags.
8. C: Login-shell CLI probes at launch (CLIVersionTelemetry, CodexMCPRegistration). Fix: persist with a TTL.

## Idle recording (90 s Time Profiler attached to the installed app)
Measured: 0.7 % CPU, 80 MB RSS, and about 360 ms of SwiftUI AttributeGraph work on main per 90 s.
Background: vImage resample, JPEG encode, `_convertJSONString`.

1. Fixed (76de88f0): the Studio queue re-encoded every `pending` batch every minute with no backoff or in-flight
   guard. `StudioUploadBackoff` now allows one upload per batch and waits 1, 2, 5, 15, 60 min after a failure.
2. Fixed (ff783850 and this change): the AppleScript privacy check compiled the script at every capture and ran
   it synchronously on main. Scripts are compiled once, skipped when no setting needs them, and run on a serial
   background queue (`AppleScriptQueue`).
3. C: 60 s timeline refresh timers keep running when the window is hidden (soft quit = `NSApp.hide`).
   They replace the whole non-Equatable `positionedActivities`, so every card re-renders
   (CanvasTimelineDataView.swift:807, Week :701, Month :118). Likely source of the AG time.
4. C: Every DB op adds a Sentry breadcrumb (`debugSlowQueries = true`, "TEMPORARY", StorageManager.swift:187).
5. C: PauseManager sends `objectWillChange` at 1 Hz while paused, which redraws MainView.

## Timeline scrolling (code audit, not yet measured)
1. C, mostly fixed: the preference callbacks still fire every scroll frame (the frames are measured
   in the outer "TimelinePane" space), but they write into plain reference boxes (`TimelineFrameBox`),
   and the only @State they touch (`weeklyHoursFadeOpacityLevel`, `weeklyHoursIntersectsCard`) is
   assigned only when its value changes (the fade level is rounded to 5 % steps). What is left is
   the per-frame callback work itself. The 24 hour-label GeometryReaders are replaced by one reader on
   the time column (label frames derived in `TimelineTimeLabelGeometry`). The footer loop (Day) now compares vertical spans only; it was never expensive (tens of cards). Needs an Animation Hitches trace to know if it matters.
2. C: Per-card cost in body: category lookup, favicon pattern matching, and an InnerGlow blur pass per card (now vector strokes, `CardEdgeGlow`)
   (CanvasActivityCard.swift:190-242, DayflowTheme.swift:712).
3. C: Cards are not lazy and the stagger animation is uncapped. The Day↔Hour switch renders two scaled timelines.
4. C: N+1 `screenshotsForBatch` for failed cards (TimelineActivityLoader.swift:92-114).

## State
- Cherry-picked a89a7640 (Release type-check timeout in FlowSessionTimeline.swift) so Release builds.
- Fixed: startup items 1, 2, 3 and 6 (5 benefits from 3), idle items 1, 2, 3 (timers while hidden) and 4 (breadcrumbs). See CHANGELOG.md.
- Open: startup 4, 7, 8; idle 5; Timeline scrolling items 2-4 and the remainder of 1 (not yet measured with Animation Hitches).
- Timeline scrolling items 2 and 3 are partly done already: the category style lookup is built once per render and the
  entrance stagger is capped (`TimelineReloadGate.entranceDelay`). Cards are still a ZStack of offset views, not lazy.
  Windowing them needs the scroll offset, which is itself a per-frame cost, so measure first.
- Traces are in the session scratchpad and are not committed.
- Caveat: the "after" launch traces did NOT measure the new build. `xctrace --launch` started
  /Applications/Dayflow.app instead of the perf build (running the perf binary directly works). The
  date-helper gain is from a micro-benchmark only (17.8 µs → 0.74 µs per call); the startup gains
  (splash skip, deferred integrity check) are not yet re-measured end to end.
