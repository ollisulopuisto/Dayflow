# Plan

Updated 2026-10-22. Working branch: `main` (pushed to `fork`, ollisulopuisto/Dayflow).
`origin` = JerryZLiu/Dayflow (upstream, v2.7.5). No local Xcode: CI
(`.github/workflows/build-macos.yml`, now builds and runs DayflowTests) is the only
compiler and test runner.

## Done (on main)
- Merged upstream v2.7.5 (`da6d627b`). Conflict in StorageManaging resolved.
- Screenshot source fallback and day cache (`TimelineReviewFrameLoading.swift`):
  card bounds, then activity bounds; prefetched day answers without DB reads;
  binary search on the sorted day cache.
- Regression tests: `DayflowTests/TimelineReviewScreenshotSourceTests.swift`.
- Week view macroblocks (10-minute blocks, dominant category) with tests.
- Studio incomplete-import and card-save failure logging.
- CI now runs DayflowTests (it previously only built the app).

## Upstream sync
- `.github/workflows/sync-upstream.yml` runs daily (00:00 UTC) and on demand.
  Merges `JerryZLiu/Dayflow` main into `sync/upstream-main`, opens or updates a PR,
  then dispatches the macOS build and tests on that branch.
- Conflicts: nothing is pushed. The run fails and lists the files.
- Verified: "up to date" path (run 39791719832, success, sync skipped). Dry run of the
  conflict path in a scratch clone detected the conflicting file.
- Not yet verified end to end: a real upstream commit producing a PR.
- Needs a repository secret `SYNC_TOKEN` (PAT with `workflow` scope) for syncs that
  touch `.github/workflows/`. Add it in GitHub settings, not in chat.

## In flight / to verify
- Red check: `redcheck-mutant` branch (fallback removed) must fail
  `testFallsBackToActivityBoundsWhenCardBoundsHoldNoScreenshots`. Result pending;
  the branch is deleted once checked.
- CI run on main with the test step: confirm green.

## Open decisions
- `fork/koti-batching-2.7.1` has 54 commits not on main: performance work
  (launch, Weekly, Timeline, Chat), Hour/Month zoom, treemap Other tiles,
  private-browser filtering, Sparkle/CI changes, Chat agy provider. Choose:
  (a) merge the whole branch into main, then delete it; or (b) keep it.
- `fork/ui-refresh-dark-mode` has 3 unique commits (dark mode refresh). Keep or delete.
- BRIEF-koti-batching.md still names branch `koti-batching`; update the name.
- Mac Studio constraints (brief): no analysis 01:00–07:00 Helsinki; one GPU job
  at a time; a gpu-queue port for Dayflow needs owner approval before changing.

## Branch cleanup (nothing deleted yet)
Fully merged into main, safe to delete:
- fork: `claude/confident-hawking-v5my0v`, `claude/practical-archimedes-n7fqbv`,
  `defer-analysis-to-idle-3702119853844756667`, `koti-batching`, `devin/1773987437-cpu-optimization`
- local: `integrate-idle-capture-main`, `koti-batching`, `restore-batch-queue-main`

Stale, one old commit each:
- fork: `claude/fix-app-launch-error-SwSZp`, `codex/weekly-timeline-font-controls`,
  `devin/1774096411-fix-app-hanging-issues`, `devin/1774332260-fix-intro-animation-replay`,
  `perf/optimize-screenshot-source-3259676437747517955` (code identical to main)

Tip SHAs before cleanup: `scratchpad/branch-tips-before-cleanup.txt` (session scratchpad).
`origin/*` branches belong to upstream; not touched.

## Parked
- Open PRs from other contributors (#380, #382, #386–#391, #400) are not ours. Not reviewed.
- PR #398 "Koti batching" is open on the fork. Close once the branch decision is made.
- No CHANGELOG.md in this repo; your global rules call for one.
