# Changelog

## Unreleased

### Added
- Studio batch analysis: analysis can run on the Mac Studio queue, and pending analysis shows as its own card in the timeline.
- Timeline: Hour and Month zoom levels; the mode switch shows all four modes.
- Week view: consecutive activities join into blocks of about 10 minutes, labelled by their dominant category. The day view keeps the fine-grained cards.
- Week view: font size and weight controls, shown in Week mode.
- Upstream sync: a daily job opens a PR when upstream JerryZLiu/Dayflow has new commits. It fails rather than pushing when a merge conflicts.

### Fixed
- Timeline: a background refresh that lands under the pointer no longer aborts the app (AttributeGraph crash). Refreshes wait until the pointer leaves the cards.
- Updates: the Sparkle installer launcher service is off, which fixes "The application can't be opened" (-10810) after an update.
- Intro video replays when the app is reopened after a soft quit.
- Launch hangs: the database integrity check runs off the main thread.
- Flow: one malformed goal task no longer drops the other goal tasks.
- Time parsing rejects out-of-range times such as "25:00 AM" and "9:60 AM".

### Tests
- Screenshot source regression tests: the card-bounds fallback, the day cache answering without database reads, and inclusive bounds.
- CI now runs the unit tests on every build. Previously it only built the app.
- Fixed the seven unit tests that were failing on main.
- Added `TimelineDateHelpersTests`.

### Performance
- Startup: the splash video is skipped after onboarding (it held the window for ~3.6 s on every launch), and the initial scroll to "now" waits 0.4 s instead of 1.5 s.
- Startup: the database integrity check and the initial storage/timelapse purges run 45 s after launch on a background queue instead of inside `StorageManager.init`, where the main thread could wait on them (the quick check alone cost ~75 ms).
- Startup: the support-chat web view starts 20 s after launch instead of during launch.
- Layout: `normalizedTimelineDate` builds the noon date from components instead of `date(bySettingHour:)`, which is ~24x faster (0.74 µs vs 17.8 µs per call). The timeline views call it thousands of times per layout pass. Results match for every day of a 2-year range, DST changes included.
- Idle: the Day, Week and Month timelines no longer reload every 60 s while the app is hidden, minimized or covered. They refresh when the app becomes active again.
- Idle: removed the per-query "DB read/write" Sentry breadcrumbs; slow and failed queries still log them.

- Idle: the Studio queue uploads each pending batch once at a time and waits 1, 2, 5, 15, then 60 minutes after a failure, instead of re-encoding every pending batch every minute while the Studio is unreachable.
- Idle: the browser privacy check compiles each AppleScript once and skips browsers no setting needs. It now asks the browser on a background queue, so a slow or hung browser no longer freezes the main thread at capture time.

### Not yet addressed
See `docs/PERFORMANCE.md` for the findings that are still open (timeline scrolling is not yet measured, and the cards are not lazy).
