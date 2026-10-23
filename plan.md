# Plan

Updated 2026-10-23. Working branch: `main`, pushed to `fork`
(ollisulopuisto/Dayflow). `origin` = JerryZLiu/Dayflow (upstream).
No local Xcode: CI (`.github/workflows/build-macos.yml`) builds and runs DayflowTests
and is the only compiler and test runner. Last green run on this tree: 319 unit tests passed.

## Done
- Upstream v2.7.5 merged.
- Kotlin batching branch merged (Studio queue, week and canvas performance,
  Hour/Month zoom, treemap, privacy filters, CI changes).
- Stale fix branches merged: intro replay, Sparkle XPC launcher off, week font
  controls, hang fixes (already on main).
- Screenshot source fallback and regression tests.
- Seven failing unit tests fixed.
- CI runs unit tests on every build.
- Daily upstream sync job (`.github/workflows/sync-upstream.yml`). Needs a
  `SYNC_TOKEN` secret (PAT with `workflow` scope) for syncs that touch workflows.
- CHANGELOG `Unreleased` section updated.
- Idle: browser privacy AppleScript runs on a background queue (CI result pending, see Open).

## Open
- Browser privacy off-main change and `BrowserPrivacyQueueTests`: pushed but not yet built or tested on CI.
  The failing-first run was skipped (the test does not compile without `AppleScriptQueue`).
- Timeline scroll performance: the preference-key and lazy-card items in `docs/PERFORMANCE.md` are not
  done. The @State-per-frame claim was already fixed; lazy cards need a measurement first.
- `fork/ui-refresh-dark-mode` (3 commits, Sept): not merged. It conflicts in 43 files,
  about 150 hunks, and the redesign overlaps with main's newer UI work. Decide
  whether to port it deliberately or drop it. Tip `13f491ee`.
- Sync job end to end: verified only the "already up to date" path. A real upstream
  commit has not produced a PR yet.
- Mac Studio constraints (from `BRIEF-koti-batching.md`): no analysis 01:00–07:00
  Helsinki; one GPU job at a time; the gpu-queue port needs owner approval.
- `BRIEF-koti-batching.md` still names branch `koti-batching`; the work lives on `main`.
- PR #398 "Koti batching" is still open on the fork. Close it.
- Open upstream PRs from other contributors are not reviewed.

## Branches
Only `main` and `fork/main` (same commit) plus `fork/ui-refresh-dark-mode` remain.
Tip SHAs for deleted branches are in the session scratchpad
(`branch-tips-before-cleanup.txt`, `branch-tips-final.txt`).
