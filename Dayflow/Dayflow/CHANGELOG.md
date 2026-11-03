# Changelog

## [Unreleased]

## [2.7.28] - 2026-11-04

### Fixed
- Allow plain-HTTP Studio uploads to the Studio's Tailscale machine name, which App Transport Security blocked even though tailnet traffic is already encrypted.
- Explain Studio upload transport failures with a fix hint when the URL scheme does not match the service (plain-HTTP service vs. `https://` URL).

## [2.7.27] - 2026-11-03

### Fixed
- Make manual Studio send clear retry backoff for pending batches while preserving in-flight protection.
- Show recent Studio upload outcomes and network errors in Storage settings.

## [2.7.26] - 2026-11-03

### Changed
- Defer automatic Studio uploads when sustained system load or serious thermal pressure indicates the Mac is busy, rather than using keyboard/mouse inactivity. Manual send can override the load check; the Studio still controls analysis timing.

## [2.7.25] - 2026-11-03

### Added
- Add a manual Studio queue send action that bypasses Dayflow's idle gate, plus a recent idle decision log in Settings.

### Fixed
- Recover screen capture after dark wake with bounded display retries and stale capture-work cancellation.
- Validate device identifiers and time zones before accepting Studio queue jobs.
- Fix idle sampling boundary and shell-escaping test expectations.
- Keep the bundled changelog in sync with CI repair notes.

### Performance
- Optimize Studio queue card parsing and time normalization.

## [2.7.24] - 2026-11-01

### Added
- Configure concurrent frame transcription for local models and use SiliconFlow as an OpenAI-compatible provider.
- Copy daily and weekly timelines as Markdown.

### Fixed
- Detect Screen Recording permission through ScreenCaptureKit and keep launch-at-login status checks off the main thread.
- Improve local-provider configuration cleanup, model connection checks, and activity-card boundary validation.
- Improve daily recap filtering and weekly dashboard summaries.

### Performance
- Build universal arm64 and x86_64 releases and bound local-model frame loading during analysis.

## [2.7.23] - 2026-10-31

### Fixed
- Keep active screen recording from being deferred or App Napped, while allowing idle system sleep; release the activity on pause (sleep/lock) and stop.

### Tests
- Cover App Nap activity acquisition, recorder state transitions, pause/resume, failed acquisition, and cleanup on deinitialization.

## [2.7.22] - 2026-10-30

### Performance
- Reduce memory footprint to 22 MB and eliminate CPU spikes via zero-copy capture and APFS remuxing.
- Integrate upstream PR 407 memory reductions.

### Fixed
- Fix duplicate FrameStore.close() redeclaration from the upstream PR 407 merge, which broke the release build.
- Deduplicate CLI person-property publications.
- Refresh persisted CLI probe cache after wall-clock rollback.

### Changed
- Support Personal Team local builds; add a local Xcode build helper and document local Mac signing requirements.


## [2.7.21] - 2026-10-29

### Changed
- Explicitly close cached HEVC frame readers on eviction, after 30 seconds idle, when recording stops, and during app shutdown.

## [2.7.20] - 2026-10-29

### Changed
- Release scripts now name the DMG `Dayflow-<version>.dmg` by default so downloaded installers are distinguishable; `DMG_NAME` still overrides.

### Fixed
- Week totals: count capture time still waiting for analysis, so the "N hours tracked this week" footer matches the visible week-grid blocks.


## [2.7.19] - 2026-10-29

### Fixed
- Week grid: keep the footer weekly tracked-activity total in sync with the grid.
- Swift argument order for the week-grid callback (broke the 2.7.18 release build, which was never published).

### Performance
- Shrink launch window-background assets.

## [2.7.17] - 2026-10-28

### Fixed
- Recording status: show the permission result without waiting for storage cleanup and scans.
- CLI argument handling and zero-duration activity processing.
- Timeline text rendering and activity coverage handling.

### Performance
- Batch database operations for recordings, observations, chat, goals, and review ratings.
- Improve timeline review category filtering and batch screenshot reads for failed cards.
- Reduce redraws during timed pauses and retain CLI version telemetry caching across launches.

### Tests
- Expand clipboard formatting, card sorting, network access, color, and duration coverage.

## [2.7.16] - 2026-10-27

### Performance
- Week timeline: render cards around the actual scroll viewport with a smaller buffer.
- Week timeline: coalesce scroll bucket updates and defer hover scaling and expanded-title measurement until hover intent is confirmed.

### Fixed
- Weekly insights: equal start and end times no longer count as 24 hours of activity.

## [2.7.15] - 2026-10-26

### Fixed
- Weekly insights: restore recorded-time totals by using SQLite-supported overlap calculations, including activity crossing the selected week's boundaries.
- Weekly insights: identify the selected week in the recording requirement message and refresh when analysis results arrive.
- Weekly navigation: support Command-Left and Command-Right with the same text-editing behavior as Timeline.
- CI: include Network in the Settings tab order test and rebuild upstream releases from main.

## [2.7.14] - 2026-10-26

### Added
- Configurable network access scopes for localhost, local network, and all network addresses in onboarding and Preferences.
- Scope-aware network gating for requests, including batched Studio analysis transfers.


## [2.7.13] - 2026-10-26

### Fixed
- CI build: copy month summary intervals into a mutable local before sorting.

## [2.7.12] - 2026-10-26

### Fixed
- CI build: restored compilation of the network access alert, month summary, and auth error mapping.

## [2.7.11] - 2026-10-26

### Fixed
- CI build: corrected static localhost checks in the network blocking protocol and fixed a malformed comment in the network access modal.

## [2.7.9] - 2026-10-25

### Added
- Studio batch analysis: analysis can run on the Mac Studio queue, and pending analysis shows as its own card in the timeline.
- Timeline: Hour and Month zoom levels; the mode switch shows all four modes.
- Week view: consecutive activities join into blocks of about 10 minutes, labelled by their dominant category. The day view keeps the fine-grained cards.
- Week view: font size and weight controls, shown in Week mode.
- Upstream sync: a daily job opens a PR when upstream JerryZLiu/Dayflow has new commits. It fails rather than pushing when a merge conflicts.

- Timeline search: a field next to the category chips (⌘F focuses it, Esc clears it). Cards that do not match are dimmed like muted categories, in Day, Hour and Week. Month day totals count only matching activities. Matches title, summaries, category, app and site; every word must match.
- ⌘← and ⌘→ step the timeline back and forward by a day, week or month (Day/Hour, Week, Month). Forward stops at today. In a text field they still move the cursor to the start or end of the line.

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
- CI: the build workflow token has `contents: write` (no step uses it yet).

### Performance
- Startup: the splash video is skipped after onboarding (it held the window for ~3.6 s on every launch), and the initial scroll to "now" waits 0.4 s instead of 1.5 s.
- Startup: the database integrity check and the initial storage/timelapse purges run 45 s after launch on a background queue instead of inside `StorageManager.init`, where the main thread could wait on them (the quick check alone cost ~75 ms).
- Startup: the support-chat web view starts 20 s after launch instead of during launch.
- Layout: `normalizedTimelineDate` builds the noon date from components instead of `date(bySettingHour:)`, which is ~24x faster (0.74 µs vs 17.8 µs per call). The timeline views call it thousands of times per layout pass. Results match for every day of a 2-year range, DST changes included.
- Idle: the Day, Week and Month timelines no longer reload every 60 s while the app is hidden, minimized or covered. They refresh when the app becomes active again.
- Idle: removed the per-query "DB read/write" Sentry breadcrumbs; slow and failed queries still log them.

- Idle: the Studio queue uploads each pending batch once at a time and waits 1, 2, 5, 15, then 60 minutes after a failure, instead of re-encoding every pending batch every minute while the Studio is unreachable.
- Idle: the browser privacy check compiles each AppleScript once and skips browsers no setting needs. It now asks the browser on a background queue, so a slow or hung browser no longer freezes the main thread at capture time.
- Scrolling: the Day and Week time columns report one measured frame per scroll frame and derive the hour-label frames from it, instead of 24 per-label layout readers. The weekly-hours footer fade is unchanged.
- Scrolling: timeline cards draw their inner edge glow with three vector strokes instead of a blurred stroke, which removes an offscreen blur pass per card. The glow is an approximation of the old one and may look slightly different at the card edge.
- Scrolling: the Day footer overlap check compares vertical spans instead of building a rectangle per card.
- Week scrolling: week cards measure their expanded height only while the pointer is on them. Every card used to lay its title out a second time, hidden, and publish the height on every update (about 0.7 s of CPU per 30 s of scrolling in a trace).
- Scrolling: Day, Hour and Week build only the cards near the viewport (about a screen of margin each way) instead of every card of the day or week. Most effective in Hour zoom, where the day is several screens tall; in Day and Week the saving is small because a day is only 2 to 3 screens.

### Not yet addressed
See `docs/PERFORMANCE.md` for the findings that are still open (timeline scrolling is not measured; the window-wide re-evaluation on scroll is not found).