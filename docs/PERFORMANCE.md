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

## Left, in impact order
1. InnerGlow blur and two always-present shadows on every card (CanvasActivityCard ~192, ~231;
   WeekTimelineActivityCard ~203). Profile first: replacing them changes the look, and an `if`
   around the shadows would change view identity on hover.
2. Week hover state lives in the grid, so every card re-evaluates on hover (WeekTimelineGridView ~427).
3. Hour view card label size: 6x zoom, 13 pt text; check readability on screen.
4. Treemap hover recomputes all layouts (WeeklyTreemapSection ~86).
5. RetryCoordinator dotTick re-renders MainView every 0.6 s while retrying.
6. Sankey hover rebuilds paths per mouse move; Chat transcript is a non-lazy VStack.
7. WeeklyAccessLockedView repeatForever animations; day cards loaded twice at launch; Sentry/PostHog setup before first frame.
8. Studio payload: cache encoded JPEGs per batch; query pending batches by status instead of allBatches().
