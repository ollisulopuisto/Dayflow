#!/usr/bin/env python3
"""Select focused XCTest suites for a push; fail closed to the full suite."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


TEST_ROOT = Path("Dayflow/DayflowTests")
TEST_CLASS = re.compile(r"(?:final )?class\s+(\w+)\s*:\s*XCTestCase\b")

# Keep these associations broad and biased toward extra coverage. Files outside
# a known area select the full suite. The weekly full run catches stale mappings.
GROUP_FILES = {
    "network": {
        "NetworkAccessLANTests.swift",
        "NetworkAccessStoreTests.swift",
        "NetworkGateTests.swift",
        "BrowserPrivacyQueueTests.swift",
        "TimelineActivityLoaderTests.swift",
    },
    "privacy": {
        "BrowserPrivacyQueueTests.swift",
        "TimelineActivityLoaderTests.swift",
        "NetworkAccessLANTests.swift",
        "NetworkAccessStoreTests.swift",
        "NetworkGateTests.swift",
    },
    "storage": {
        "StorageManagerScreenshotsTests.swift",
        "StorageManagerTimelineReviewTests.swift",
        "StorageManagerWeeklyTrackedMinutesTests.swift",
        "TimelineActivityLoaderTests.swift",
        "TimelineReviewScreenshotSourceTests.swift",
        "WeeklyDashboardBuilderTests.swift",
        "WeeklyDefaultWeekTests.swift",
    },
    "timeline": {
        "DaySummaryLoadTokenTests.swift",
        "StorageManagerWeeklyTrackedMinutesTests.swift",
        "TimelineActivityLoaderTests.swift",
        "TimelineCardWindowTests.swift",
        "TimelineClipboardFormatterTests.swift",
        "TimelineDateHelpersTests.swift",
        "TimelineReviewScreenshotSourceTests.swift",
        "TimelineScrollCostTests.swift",
        "TimelineScrollStateTests.swift",
        "TimelineSearchTests.swift",
        "TimelineStepTests.swift",
        "TimelineTimeLabelGeometryTests.swift",
        "WeeklyDashboardBuilderTests.swift",
        "WeeklyDefaultWeekTests.swift",
    },
    "ai": {
        "AgyChatStreamTests.swift",
        "ChatContentParserFastPathTests.swift",
        "ChatReplyStateTests.swift",
        "ChatStreamingRegressionTests.swift",
        "ClaudeActivityCardBoundaryTests.swift",
        "ClaudeCLIExecutionProfileTests.swift",
        "ClaudeTranscriptionInputBuilderTests.swift",
        "CodexClaudeProviderTests.swift",
        "CodexExecutableResolverTests.swift",
        "GeminiActivityCardsTests.swift",
        "GeminiAPIHelperTests.swift",
        "GeminiDashboardModelFallbackTests.swift",
        "LLMProviderRoutingTests.swift",
        "LocalChatLoopTests.swift",
        "OpenAICompatibleConfigurationTests.swift",
        "OpenAICompatibleProviderTests.swift",
        "ProviderPromptPreferencesTests.swift",
        "ProvidersSettingsViewModelTests.swift",
        "SupportChatContextTests.swift",
    },
    "chat": {
        "AgyChatStreamTests.swift",
        "ChatContentParserFastPathTests.swift",
        "ChatReplyStateTests.swift",
        "ChatStreamingRegressionTests.swift",
        "LocalChatLoopTests.swift",
        "SupportChatContextTests.swift",
    },
    "flow": {
        "FlowNativeSnapshotTests.swift",
        "FlowNativeStateTests.swift",
        "FlowWaitlistRegistrationTests.swift",
    },
    "agents": {
        "AgentClientRegistrationTests.swift",
        "AgentPlaybackUsageTests.swift",
        "AgentUsageTelemetryQueueTests.swift",
        "AgentWriteHandlersTests.swift",
        "CLIVersionTelemetryTests.swift",
        "CodexExecutableResolverTests.swift",
    },
    "localization": {"LocalizationTests.swift", "LocalizedDurationTests.swift"},
}

SMOKE_FILES = {
    "LaunchIntroTests.swift",
    "LocalizationTests.swift",
    "NetworkGateTests.swift",
    "TimeParsingTests.swift",
    "TimelineStepTests.swift",
}


def full_suite(reason: str) -> tuple[str, list[str], str]:
    return "full", [], reason


def changed_paths(event_name: str, event: dict[str, object]) -> tuple[list[str] | None, str]:
    if event_name == "schedule":
        return None, "scheduled full-suite run"

    before = event.get("before")
    after = event.get("after") or os.environ.get("GITHUB_SHA")
    if not isinstance(before, str) or not isinstance(after, str):
        return None, "event has no push range"
    if not before or set(before) == {"0"}:
        return None, "push has no usable base commit"

    result = subprocess.run(
        ["git", "diff", "--name-only", before, after],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None, "could not compare push commits"
    paths = [line for line in result.stdout.splitlines() if line]
    if not paths:
        return None, "empty or unavailable change range"
    return paths, "push range inspected"


def classes_for_files(files: set[str]) -> set[str] | None:
    classes: set[str] = set()
    for filename in files:
        path = TEST_ROOT / filename
        if not path.is_file():
            return None
        found = TEST_CLASS.findall(path.read_text(encoding="utf-8"))
        if not found:
            return None
        classes.update(found)
    return classes


def select(event_name: str, event: dict[str, object]) -> tuple[str, list[str], str]:
    if event_name != "push":
        return full_suite(f"{event_name} event")

    paths, reason = changed_paths(event_name, event)
    if paths is None:
        return full_suite(reason)

    groups: set[str] = set()
    explicit_test_files: set[str] = set()
    for path in paths:
        if path.startswith(f"{TEST_ROOT}/") and path.endswith(".swift"):
            explicit_test_files.add(Path(path).name)
            continue

        if path.startswith(".github/") or path.startswith("scripts/ci/"):
            return full_suite(f"CI configuration changed: {path}")
        if path.endswith((".pbxproj", ".xcconfig", ".entitlements", ".xcworkspacedata")):
            return full_suite(f"Xcode configuration changed: {path}")

        if "/Resources/" in path or ".lproj/" in path or path.endswith("Localizable.strings"):
            groups.add("localization")
        elif "Core/AI/" in path:
            groups.add("ai")
        elif "Core/Flow/" in path:
            groups.update({"flow", "agents"})
        elif "Core/Net/" in path or "NetworkAccess" in path:
            groups.add("network")
        elif "Core/Recording/" in path:
            groups.update({"storage", "timeline", "privacy"})
        elif (
            "Core/Thumbnails/" in path
            or "Views/UI/MainView/" in path
            or "TimelineReview" in path
        ):
            groups.update({"storage", "timeline"})
        elif "Views/UI/SupportChat" in path or "Core/Chat/" in path:
            groups.add("chat")
        elif "Core/Agent" in path or "Core/CLI/" in path:
            groups.add("agents")
        elif "Core/Localization/" in path:
            groups.add("localization")
        elif path.endswith(".swift"):
            return full_suite(f"unmapped Swift source: {path}")
        elif path.startswith("Dayflow/Dayflow/"):
            return full_suite(f"unmapped app resource or source: {path}")
        else:
            return full_suite(f"unmapped changed file: {path}")

    suites = classes_for_files(explicit_test_files)
    if suites is None:
        return full_suite("changed test file has no discoverable XCTestCase class")
    for group in groups:
        group_classes = classes_for_files(GROUP_FILES[group])
        if group_classes is None:
            return full_suite(f"test mapping for {group} is stale")
        suites.update(group_classes)

    smoke = classes_for_files(SMOKE_FILES)
    if smoke is None:
        return full_suite("smoke-test mapping is stale")
    suites.update(smoke)

    if not suites:
        return full_suite("no focused test suites matched")
    return "selected", sorted(suites), ", ".join(sorted(groups)) or "changed tests only"


def main() -> int:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    event_name = os.environ.get("GITHUB_EVENT_NAME", "unknown")
    try:
        event = json.loads(Path(event_path).read_text(encoding="utf-8")) if event_path else {}
    except (OSError, json.JSONDecodeError) as error:
        mode, suites, reason = full_suite(f"could not read event payload: {error}")
    else:
        mode, suites, reason = select(event_name, event)

    print(f"mode={mode}")
    print(f"suites={','.join(suites)}")
    print(f"reason={reason.replace(chr(10), ' ')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
