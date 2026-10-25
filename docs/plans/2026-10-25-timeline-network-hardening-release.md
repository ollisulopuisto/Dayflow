# Timeline and Network Hardening Release Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Correct timeline aggregation and network permission coordination, then produce and publish a versioned Dayflow DMG artifact.

**Architecture:** Assign each timeline activity's covered interval to each overlapping 4 AM-bounded day, and allocate overlapping time to one category deterministically. Use calendar day boundaries for week columns and fan a single permission response out to all waiting network requests.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode, Git, codesign, create-dmg.

---

### Task 1: Correct month activity day splitting

**Files:**
- Modify: `Dayflow/Dayflow/Views/UI/MainView/MonthTimelineView.swift`

Split each positive-duration activity at every 4 AM timeline-day boundary before summarizing. Preserve search and category filters and ensure category and total seconds count each covered second once.

### Task 2: Verify the earlier review fixes

**Files:**
- Review: `Dayflow/Dayflow/Views/UI/MainView/WeekTimelineGridView.swift`
- Review: `Dayflow/Dayflow/System/NetworkAccessCoordinator.swift`

Confirm week splitting uses calendar boundaries, overlapping category accounting is unique and deterministic, and concurrent network requests resume from one decision.

### Task 3: Version, build, and inspect the release artifact

Bump the patch version and build number, build the Release app and DMG, and verify the artifact exists and has the expected version.

### Task 4: Commit and publish the requested Git refs

Commit all release changes, push the commit, create the matching version tag, and push the tag.
