# Low Impact Studio Queue Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce memory use and periodic foreground work while retaining reliable screenshot batches and Studio results.

**Architecture:** Generate each JSON upload into a temporary file, encoding one selected screenshot at a time, then upload that file with a low-priority URLSession task. In Studio mode, wait for an idle window before querying a bounded page of unbatched screenshots; saved batch membership itself is the durable cursor, so older captures remain eligible after long active sessions. Keep retry and result-poll scheduling in a small synchronized in-memory policy with capped exponential delays.

**Tech Stack:** Swift, Foundation URLSession, SQLite/GRDB storage layer, DispatchQueue.

---

### Task 1: Bound Studio upload memory

**Files:**
- Modify: `Dayflow/Dayflow/Core/Analysis/StudioBatchQueue.swift`

Replace the array of base64 image dictionaries plus whole-request `Data` with a temporary-file JSON writer. Write job metadata once and append one encoded screenshot object at a time, then use `URLSession.uploadTask(with:fromFile:)`. Remove the temporary file on all failure paths and on task completion. Keep the existing screenshot sample limit and low task priority.

**Validation:** Inspect all cleanup paths and run `git diff --check`; use the GitHub macOS build for compiler validation.

### Task 2: Defer and bound Studio batching bookkeeping

**Files:**
- Modify: `Dayflow/Dayflow/Core/Analysis/AnalysisManager.swift`
- Modify: `Dayflow/Dayflow/Core/Recording/StorageManaging.swift`
- Modify: `Dayflow/Dayflow/Core/Recording/StorageManager+Screenshots.swift`
- Modify: `Dayflow/Dayflow/Core/Recording/StorageManager+TimelineCards.swift`

Return from the Studio processing pass before screenshot queries while the Mac is active. During idle windows, fetch at most 500 unbatched screenshots at a time, without the non-Studio 24-hour cutoff. Persisted batch-to-screenshot links act as the durable cursor: completed groups leave the next page, while an incomplete final group remains queryable until more captures arrive. Query pending Studio batches directly from SQLite with a fixed limit instead of loading all historical batches.

**Validation:** Review the SQL ordering, `LIMIT`, status filters, and incomplete-tail behavior; run `git diff --check` and use the GitHub macOS build for compiler validation.

### Task 3: Add capped retry and result-poll backoff

**Files:**
- Modify: `Dayflow/Dayflow/Core/Analysis/StudioBatchQueue.swift`

Track the next upload attempt per batch and the next results poll time behind the existing lock. Increase delays exponentially after failures or empty result polls, cap upload retries at 15 minutes and empty-result polling at 5 minutes, and reset delays after a successful upload or non-empty result response. Leave network requests low priority and ensure only one upload and one poll are active at once.

**Validation:** Review success, empty-result, error, and activity-resumed paths; run `git diff --check` and use the GitHub macOS build for compiler validation.

### Task 4: Show captured periods awaiting analysis

**Files:**
- Modify: `Dayflow/Dayflow/Core/Recording/StorageManaging.swift`
- Modify: `Dayflow/Dayflow/Core/Recording/StorageManager+TimelineCards.swift`
- Modify: `Dayflow/Dayflow/Views/UI/MainView/TimelineActivityLoader.swift`
- Modify: `Dayflow/Dayflow/Views/UI/TimelineDataModels.swift`
- Modify: `Dayflow/Dayflow/Views/UI/CanvasTimelineDataView.swift`
- Modify: `Dayflow/Dayflow/Views/UI/CanvasActivityCard.swift`
- Modify: `Dayflow/Dayflow/Views/UI/MainView/WeekTimelineGridView.swift`
- Modify: `Dayflow/Dayflow/Views/UI/MainView/WeekTimelineActivityCard.swift`

Expose pending batch intervals and unassigned screenshot timestamps from storage. Merge neighboring pending spans and add a non-editable placeholder activity with the captured interval and the message “Captured, waiting for analysis” to day and week timeline data. Pending spans should disappear on the next timeline refresh once result import creates completed cards.

**Validation:** Check 4 AM day boundaries, empty days, merged intervals, and card tap behavior by code review; use `git diff --check` and the GitHub macOS build for compiler validation.

### Task 5: Package the GitHub build as a DMG

**Files:**
- Modify: `.github/workflows/build-macos.yml`

Keep the app ZIP and add a compressed macOS disk image containing the built app. Upload both files as artifacts from the same build SHA so the requested DMG is available even when a local full Xcode installation is absent.

**Validation:** Confirm the workflow runs on `koti-batching`, `hdiutil` packages the Release app, and both artifact paths are uploaded; verify the resulting artifact after the GitHub run completes.
