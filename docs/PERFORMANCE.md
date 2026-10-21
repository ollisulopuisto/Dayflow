# Performance work (2026-10-21)

Found by static review; nothing was profiled. Confirm with Instruments on a Mac with Xcode.

## Done (branch koti-batching-2.7.1, not yet run on a Mac)
- Studio queue: in-flight guard and 1/2/5/15/60 min backoff; no per-upload results fetch (likely cause of ~40% CPU).
- Launch: intro video only before onboarding; DB quick_check off init; legacy path migration once; support chat WKWebView +5 s; agent config repair +3 s.
- Timeline: scroll frames no longer stored as state; 60 s refresh skips unchanged cards; entrance stagger capped at 0.3 s.
- Weekly: 52-week search and access count off the main thread.
- Browser privacy: skip unneeded checks, cache compiled AppleScript, 2 s timeout.
- View refresh timers skip their tick while no Dayflow window is on screen (Cmd-Q only hides).
- Day and Week cards: category colour lookup built once per render, not per card.
- Chat: chart regex compiled once; replies without a chart skip it.
- Day cards load once at launch (onAppear and didBecomeActive no longer both read the database).
- Daily goal prompt check: its three database reads run off the main thread.
- Weekly treemap hover re-renders only the hover card; Sankey hover uses prebuilt hit paths.
- Locked Weekly screen: endless animations pause while the window is inactive.
- Studio tick and uploads query batches by status and id instead of reading every batch.

## Left, in impact order
1. InnerGlow blur and two always-present shadows on every card (CanvasActivityCard ~192, ~231;
   WeekTimelineActivityCard ~203). Profile first: replacing them changes the look, and an `if`
   around the shadows would change view identity on hover.
2. Week hover state lives in the grid, so every card re-evaluates on hover (WeekTimelineGridView ~427).
3. Hour view card label size: 6x zoom, 13 pt text; check readability on screen.
4. RetryCoordinator dotTick re-renders MainView every 0.6 s while a retry runs (dots are baked
   into the status string the cards draw).
5. Chat transcript is a non-lazy VStack; switching to LazyVStack needs checking against
   scroll-to-bottom.
6. Sentry and PostHog setup run before the first frame (kept: crash reporting should start early).
