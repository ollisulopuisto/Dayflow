# CI Runtime and Hotfix Path Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce wasted macOS CI minutes and make an explicit no-tests hotfix build path available without weakening the normal test run.

**Architecture:** Keep unit tests on relevant branch pushes, without repeating a separate Release build and artifact package on every push. Cancel superseded runs, skip app CI for documentation-only changes, and add an opt-in `skip_tests` input for manual Release artifact builds. Keep tag-triggered releases as the fastest DMG path and reject unsafe manual release dispatches from branches.

**Tech Stack:** GitHub Actions, Xcode build and XCTest, Markdown documentation.

---

### Task 1: Reduce stale macOS CI runs

**Files:**
- Modify: `.github/workflows/build-macos.yml`

Add branch-scoped concurrency cancellation and ignore documentation-only changes for push runs. Run tests on normal pushes; reserve Release build and packaging for manual builds and tagged releases to avoid the duplicate configuration build on every commit.

### Task 2: Add an explicit urgent build switch

**Files:**
- Modify: `.github/workflows/build-macos.yml`
- Modify: `.github/workflows/release.yml`

Add a manual `skip_tests` input to the build workflow; only that explicit choice skips unit tests. Validate manual release dispatch refs so a branch dispatch cannot attempt to publish a `main` release. Tag pushes remain the quickest release path.

### Task 3: Document routine and hotfix paths

**Files:**
- Create: `docs/ci-release.md`

Explain when CI runs, what gets canceled/skipped, how to request a quick artifact build, and how a tagged hotfix DMG is built.

### Task 4: Validate workflow changes

Run a local workflow syntax check if available, inspect the diff, and rely on the pushed GitHub Actions run for runner validation. Report its status without waiting indefinitely for macOS queue availability.
