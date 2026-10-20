# Studio Batch Queue Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Queue completed Dayflow screenshot batches on the always-on Mac Studio, analyze them serially only during the configured GPU availability window, and import results on the laptop after it wakes.

**Architecture:** Dayflow continues recording locally and uploads completed batch archives to an authenticated, local Studio queue service before sleep. A Studio worker persists the queue, observes the Helsinki processing window, and submits one job at a time to the configured OpenAI-compatible GPU queue endpoint. The laptop fetches completed results after waking and stores timeline cards in its existing database.

**Tech Stack:** Swift, SwiftUI, URLSession, SQLite/GRDB; Python 3 standard library HTTP service and worker; launchd on macOS.

---

### Task 1: Define persistent schedule and transfer preferences

- Add defaults for Studio queue URL, shared token, timezone, processing window, and batch duration.
- Add GUI controls in Settings for endpoint, token, start/end time, and batch duration.

### Task 2: Make laptop queue batches instead of calling the model

- Continue grouping finalized screenshots into batches.
- Stop background image inference on the laptop.
- Upload pending batches to the Studio service and mark their durable queue status.
- Keep retries idempotent and do not discard local recordings.

### Task 3: Add Studio queue service and worker

- Provide authenticated enqueue and completed-result endpoints backed by disk files.
- Process jobs serially only within the configured Europe/Helsinki window.
- Call the local GPU queue endpoint; never call a cloud provider.
- Persist intermediate and final status across service restarts.

### Task 4: Import completed timeline results on laptop wake

- Poll/download finished batch results when Dayflow starts and periodically while awake.
- Validate batch IDs, timestamps, category values, and result schema before persistence.
- Mark imported batches complete and make repeated imports idempotent.

### Task 5: Document Studio deployment and operational checks

- Add launchd templates and setup instructions for the Studio worker.
- Document firewall/Tailscale binding, token setup, processing hours, and result retention.
- Build the app and worker; do not run tests unless explicitly requested.
