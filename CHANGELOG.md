# Changelog

## Unreleased

### Performance
- Startup: the splash video is skipped after onboarding (it held the window for ~3.6 s on every launch), and the initial scroll to "now" waits 0.4 s instead of 1.5 s.
- Startup: the database integrity check and the initial storage/timelapse purges run 45 s after launch on a background queue instead of inside `StorageManager.init`, where the main thread could wait on them (the quick check alone cost ~75 ms).
- Startup: the support-chat web view starts 20 s after launch instead of during launch.
- Layout: `normalizedTimelineDate` builds the noon date from components instead of `date(bySettingHour:)`, which is ~24x faster (0.74 µs vs 17.8 µs per call). The timeline views call it thousands of times per layout pass. Results match for every day of a 2-year range, DST changes included.
- Idle: the Day, Week and Month timelines no longer reload every 60 s while the app is hidden, minimized or covered. They refresh when the app becomes active again.
- Idle: removed the per-query "DB read/write" Sentry breadcrumbs; slow and failed queries still log them.

### Tests
- Added `TimelineDateHelpersTests`.

### Not yet addressed
See `docs/PERFORMANCE.md` for the measured and code-audited findings that are still open (Timeline scroll preference-key updates, Studio queue retries, main-thread AppleScript privacy check).
