# Plan

Updated 2026-10-22. Branch `restore-batch-queue-main` (= `fork/main`, tip fc021e83).
Remotes: `fork` = ollisulopuisto/Dayflow (ours), `origin` = JerryZLiu/Dayflow (upstream).
No local Xcode: CI (`build-macos.yml`) is the only compiler and test runner.

## Done
- Studio batch queue, idle-aware capture, deferred analysis: in `fork/main`.
- Timeline screenshot N+1 fixes: in `fork/main` (commit 8713680e and earlier).

## In flight / to verify
1. Screenshot fallback in `TimelineReviewScreenshotSource.screenshots(for:)`
   (`Dayflow/Dayflow/Views/UI/TimelineReviewFrameLoading.swift`).
   - Code now tries the timeline card bounds, then falls back to the activity bounds.
   - Code now skips the DB when the day cache covers the range.
   - Not verified: no regression test exists, and nothing has been run.
   - Next: add a test that fails on the pre-fix behaviour (red), confirm it passes on fc021e83 (green), run CI.
2. Upstream drift: `origin/main` has 56 commits that `fork/main` does not have. Decide when to merge.

## Open decisions
- Studio batch work is split across two lines. `koti-batching-2.7.1` (fork tip 2026-10-22) holds 4 commits not in `fork/main` by patch-id:
  - 059d6cbd CI: build on macos-26
  - 3b8672bd Debug: log why Studio results are not saved as timeline cards
  - 57c7aafb Week view: join consecutive same-category blocks into macroblocks
  - 7ad45661 Week view: 10-minute blocks take the dominant category
  Decide: port these 4 into `fork/main`, or keep `koti-batching-2.7.1` as the working line.
- PR #398 "Koti batching" (`ollisulopuisto:koti-batching`) is open. Its head `fork/koti-batching` is already contained in `fork/main`. Check whether it can be closed.
- Brief says the batching branch is `koti-batching`; the work moved to `koti-batching-2.7.1`. `BRIEF-koti-batching.md` needs the branch name updated.
- Mac Studio constraints, per the brief: no analysis 01:00–07:00 Helsinki; one GPU job at a time; gpu-queue port for Dayflow (8103 proposed) needs the owner's approval before changing.

## Branch cleanup (proposed, nothing deleted yet)
Local:
- `integrate-idle-capture-main`, `koti-batching`: fully contained in `fork/main`. Safe to delete locally.
- `main`: 190 commits behind `origin/main`. Fast-forward or delete.
- `restore-batch-queue-main`: current, identical to `fork/main`.
- `koti-batching-2.7.1`: active, see Open decisions.

Remote (`fork`), merged into `origin/main`, safe to delete after confirmation:
- `claude/confident-hawking-v5my0v`
- `claude/practical-archimedes-n7fqbv`

Remote (`fork`), contained in `fork/main`, delete after confirmation:
- `defer-analysis-to-idle-3702119853844756667` (PR #21 branch)
- `koti-batching`

Remote, unmerged, possibly stale (single old commit each, check before deleting):
- `claude/fix-app-launch-error-SwSZp` (2025-12-30)
- `devin/1773987437-cpu-optimization` (2026-03-20)
- `devin/1774096411-fix-app-hanging-issues` (2026-03-21)
- `devin/1774332260-fix-intro-animation-replay` (2026-03-24)
- `codex/weekly-timeline-font-controls` (2026-05-11)
- `ui-refresh-dark-mode` (2026-09-03, 3 commits, also on `origin`)
- `flow-fire-defringe` (`origin` only, 2026-10-12, 1 commit: fire clip de-fringe)

Remote, unmerged, possibly superseded:
- `perf/optimize-screenshot-source-3259676437747517955` (2026-10-20). Its commit 385cddc6 has the same title as 8713680e on main but is not patch-identical. Compare before deleting.

## Parked
- Open upstream PRs from other contributors (#380, #382, #386–#391) are not ours. Not reviewed.
