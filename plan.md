# Plan

Updated 2026-10-23. Working branch: `main`, pushed to `fork`
(ollisulopuisto/Dayflow). `origin` = JerryZLiu/Dayflow (upstream).
No local Xcode: CI (`.github/workflows/build-macos.yml`) builds and runs DayflowTests
and is the only compiler and test runner. Last green run on this tree: 319 unit tests passed.

## Done
- Week view missing afternoon/evening cards (reported 2026-11-11): the lazy-card band was
  driven by geometry in the ScrollView's own coordinate space, which never updates while
  scrolling on macOS, so the band stayed pinned to the top of the grid (4 AM to early
  afternoon). Fixed by deriving the scroll offset from two "TimelinePane"-space measurements
  (cards layer top vs scroll viewport top), the same geometry source the day timeline's card
  window already uses. Regression tests on the offset math; interactive scroll verification
  still needs a real Mac. Version 2.8.4 / 176.
- App Nap: `AppNapGuard` holds a `.userInitiatedAllowingIdleSystemSleep` `ProcessInfo`
  activity while the recorder is starting/capturing (released on pause/stop), so
  capture work is not deferred while idle system sleep remains allowed.
  Unit tests in DayflowTests/AppNapGuardTests.swift; CI is the only compiler.

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
- Idle: browser privacy AppleScript runs on a background queue (merged, CI green).
- Scroll: one time-column reader instead of 24 label readers (merged, CI green).

## Open
- Timeline search and ⌘←/⌘→ (merged, CI green, not yet tried in the app). Check: ⌘← in the
  search field and in Chat still moves the cursor; search dims the right cards in Day, Week and Month; in Day/Week
  merged ~10 minute blocks only match on the text of the block's main activity.
- Scroll trace findings (Day, Week, 30 s each, 2026-10-23): ~50-60 % of a core on the main thread, nearly all in
  SwiftUI internals; the whole MainView (header, right panel, mode switch) re-evaluates while scrolling. The state that
  triggers it is not found yet. Week-card hidden measurement fixed and merged (CI green; hover not yet tried in the app).
- Browser privacy off-main change: CI green but not tried against a real browser (incognito, excluded site).
- Timeline scroll time-column change: not measured on a device; label height is estimated.
- Timeline scroll, card edge glow now vector strokes (`CardEdgeGlow`): a visual approximation, check it by eye
  in light and dark themes. Merged, CI green.
- Lazy cards: root cause of the week-view miss found and fixed 2026-11-11 (see Done). Still to
  check in the app: cards popping in at the edges when scrolling fast, and after the initial
  scroll to "now".
- `fork/ui-refresh-dark-mode` (3 commits, Sept): not merged. It conflicts in 43 files,
  about 150 hunks, and the redesign overlaps with main's newer UI work. Decide
  whether to port it deliberately or drop it. Tip `13f491ee`.
- Sync job end to end: verified only the "already up to date" path. A real upstream
  commit has not produced a PR yet.
- Mac Studio constraints (from `BRIEF-koti-batching.md`): no analysis 01:00–07:00
  Helsinki; one GPU job at a time; the gpu-queue port needs owner approval.
- `BRIEF-koti-batching.md` still names branch `koti-batching`; the work lives on `main`.
- PR #398 "Koti batching" lives on upstream (JerryZLiu/Dayflow), not the fork, and is already closed (not merged).
- Open upstream PRs from other contributors are not reviewed.

## Branches
Only `main` and `fork/main` (same commit) plus `fork/ui-refresh-dark-mode` remain.
Tip SHAs for deleted branches are in the session scratchpad
(`branch-tips-before-cleanup.txt`, `branch-tips-final.txt`).

## PR #99 follow-up (2026-11-08, Instinct)

- Fixed the Devin review finding: `/v1/ack` now runs both result and complete-directory
  resolution inside its filesystem error handler. Cyclic links (`RuntimeError` on
  older Python or `OSError` on newer versions) and permission failures return JSON
  HTTP 500 rather than dropping the connection.
- Kept the containment guard, directory-relative access, `O_NOFOLLOW`, and device
  ownership check. No service configuration, deployment, or release changes.
- Added HTTP regression tests for a real cyclic link, errors from both resolve
  calls, an external symlink, owned-result acknowledgment/retry, and foreign ownership.
- Validation: the new regressions reproduced five errors before the fix; all 41
  queue tests pass after it. Ruff default E4/E7/E9/F checks pass; the stricter
  inherited configuration has existing warnings, with no new warnings introduced.
- Native macOS tests and CodeQL will be checked on the pushed PR, not claimed locally.

## Release 2.8.1 preparation (2026-11-08, Instinct)

- Release requested after Olli merged #99. Bump marketing version to 2.8.1 and
  build to 173; include the Studio queue acknowledgment fixes in both changelogs.
- Keep automatic What's New and the existing app-menu release notes; add the
  same release-notes action in Help to match the GUI baseline.
- Existing standard public-repository release workflow remains direct-to-Release,
  without Actions cache/artifact writes. Explicit arm64 build, packaged version
  and changelog checks, Gatekeeper assessment, and published SHA-256 sidecar added.
- Local host has no Swift/Xcode, so no native compile or UI acceptance is claimed.
  Shell syntax, YAML, diff hygiene and Python queue regressions checked locally;
  native compile/tests are checked in PR CI before Olli's merge and tag dispatch.
- Human-led merge only. No tag or release until this preparation is merged.

## 2026-11-08 - Release credential transport hardening

Keep certificate/keychain passwords out of process argv via security -i stdin;
store notary credentials via echo-disabled private TTY and use keychain profiles
for submit/log. Child environments drop secret aliases, errors withhold output,
and line-protocol values reject newline/NUL injection. Reuse the Kuulas transport
pattern, with dummy-data regression tests and an actual disposable macOS keychain
smoke check before real credential setup. Bare-filename checksums are retained.
Release routes remain direct GitHub Releases without cache/artifact writes.
PR only, no merge/tag/build. Native smoke validation awaits macOS CI.
## Release 2.8.1 metadata correction (2026-11-08, Instinct)

- Final review of #100 found literal Info.plist versions were not updated with
  project settings. Correct the plist to 2.8.1/173 and update the metadata contract.
- Release tag held: packaged-version guard would reject the stale bundle.
- Local upstream-merge contract tests and plist/project consistency checks pass.

## 2026-11-08 - Require signing identity before notarization

Follow-up to #102: release import now fails immediately if the signing
certificate is absent, rather than reaching notary setup with a nonexistent
keychain or publishing an unsigned app. This release route already requires
notarization; no unsigned release fallback is supported. Local guards pass.

## 2026-11-08 - Keychain search preservation and failure regression

Preserve the original keychain search list when importing a CI identity. Fail
closed on stderr even if the interpreter exits zero, and add a real native
negative smoke check (unlock nonexistent keychain must raise with output withheld).
One-command security -i status is retained in Apple's source; native CI verifies
actual runner behavior. No tag/build/merge; local synthetic tests pass.

## 2026-11-11 - Repair upstream v2.9.0 sync

- Reproduced run 42964667287: ten merge-conflicted files, not a token failure.
- Merge upstream 33517b1c into fork main 5fedfc15 on a review branch; preserve
  provider consent, disabled Flow/support startup, Studio queue, capture-generation
  locks, idle throttling, timeline windowing/search and disabled upstream updater.
- Keep the direct sample-buffer path when Privacy Shield is off. When it is on,
  convert the frame for local masking before storage and fail closed if masking
  and placeholder creation fail. Preserve capture-generation checks after awaits.
- Capture the selected docket provider and thread before awaiting consent, then
  pass those choices to the handoff instead of reading changed settings later.
- Adopt upstream browser categories alongside the existing fail-closed browser
  controls. Keep both sets of preferences; neither silently resets the other.
- Version 2.9.0, fork build 176 (do not regress to upstream build 141).
- Local Python contract, credential and queue tests pass. Native macOS compilation,
  XCTest and actual UI rendering are not available locally; await public macOS PR
  CI. UI acceptance remains unverified, including the combined privacy settings
  and footer. No merge, tag, release or Actions storage upload.

### PR #115 review follow-up
- Address Devin's four findings: continuing desktop threads use the app handoff,
  rather than a CLI invocation that cannot resume their desktop session IDs.
- Custom site rules preserve full hostnames and match only that host and its
  descendants; category matching still uses registrable domains.
- Private/unknown windows still check site rules when whole-window hiding is off.
- Pixelation errors (including individual crop/buffer failures) throw into the
  recorder's placeholder/drop path instead of returning any original secret pixels.
- Added native regression coverage for custom-host scope, private/unknown site
  checks, and injected pixelation failure. Native tests await PR CI.

### PR #115 second review pass
- Do not send threaded tasks to a web/Classic fallback when the owning desktop
  app or its thread deep link is unavailable. Explain the missing app and stop
  before provider consent, handoff history or transmission.
- Canonicalize custom internationalized domains through Foundation URL's IDNA
  host form so Unicode and punycode rules match the same hostname. Added tests.

### PR #115 native compilation follow-up
- The app compiled on macOS; test compilation found an upstream/fork test-class
  collision, both named BrowserPrivacyDecisionTests. Rename the upstream category
  suite to BrowserCategoryPrivacyDecisionTests; keep both suites and all assertions.
- Devin confirmed all six findings resolved on 829bffb1. No new findings at recheck.

### PR #115 native test follow-up
- Native compile and the new privacy regressions pass, including Unicode/punycode
  matching and injected pixelation failure. One existing exact sidebar-order test
  rejects the added Permissions tab. Keep Storage first/default and Account
  second-to-last, place Permissions after Privacy, and extend that exact assertion
  to include the new upstream tab without weakening the established ordering.
