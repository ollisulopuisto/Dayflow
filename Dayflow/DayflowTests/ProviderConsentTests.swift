//
//  ProviderConsentTests.swift
//  DayflowTests
//

import XCTest

@testable import Dayflow

final class ProviderConsentTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: ProviderConsentStore!

  override func setUp() {
    super.setUp()
    suiteName = "ProviderConsentTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    store = ProviderConsentStore(defaults: defaults)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testLocalAndLANHostsNeedNoConsent() {
    XCTAssertNil(ProviderConsentDescriptors.forHTTPURL(URL(string: "http://localhost:11434/v1")))
    XCTAssertNil(ProviderConsentDescriptors.forHTTPURL(URL(string: "http://127.0.0.1:11434/v1")))
    XCTAssertNil(ProviderConsentDescriptors.forHTTPURL(URL(string: "http://192.168.1.20:8080/v1")))
    XCTAssertNil(ProviderConsentDescriptors.forHTTPURL(URL(string: "https://mac-studio.local/v1")))
  }

  func testGeminiHostMapsToNamedDescriptor() {
    let descriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "https://generativelanguage.googleapis.com/v1beta/models"))
    XCTAssertEqual(descriptor?.key, "http.generativelanguage.googleapis.com")
    XCTAssertEqual(descriptor?.destination, "generativelanguage.googleapis.com")
    XCTAssertFalse(descriptor?.providerName.isEmpty ?? true)
    // Timeline prompts include the user's full name; the disclosure must say so.
    XCTAssertTrue(descriptor?.dataSummary.contains("name") ?? false)
  }

  func testOpenRouterHostMapsToNamedDescriptor() {
    let descriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "https://api.openrouter.ai/api/v1/chat/completions"))
    XCTAssertEqual(descriptor?.key, "http.api.openrouter.ai")
    XCTAssertEqual(descriptor?.providerName, "OpenRouter")
  }

  func testUnknownInternetHostFallsBackToHostScopedKey() {
    let descriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "https://llm.example.com/v1/chat/completions"))
    XCTAssertEqual(descriptor?.key, "http.llm.example.com")
    XCTAssertEqual(descriptor?.destination, "llm.example.com")
  }

  func testNonDefaultPortIsPartOfTheKey() {
    let descriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "https://llm.example.com:8443/v1/chat/completions"))
    XCTAssertEqual(descriptor?.key, "http.llm.example.com:8443")
    XCTAssertEqual(descriptor?.destination, "llm.example.com:8443")
  }

  func testDefaultPortIsDroppedFromTheKey() {
    let descriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "https://llm.example.com:443/v1/chat/completions"))
    XCTAssertEqual(descriptor?.key, "http.llm.example.com")
    let httpDescriptor = ProviderConsentDescriptors.forHTTPURL(
      URL(string: "http://llm.example.com:8080/v1/chat/completions"))
    XCTAssertEqual(httpDescriptor?.key, "http.llm.example.com:8080")
  }

  /// One prompt per provider covers every send path: the disclosure names all
  /// data shapes (screenshots, extracted text, prompts, Daily Brief task text)
  /// and every destination, including the web fallback the docket handoff uses
  /// when the provider's desktop app is not installed.
  func testCLIDescriptorsCoverEverySendPath() {
    let claude = ProviderConsentDescriptors.forCLITool(.claude)
    XCTAssertTrue(claude.destination.contains("api.anthropic.com"))
    XCTAssertTrue(claude.destination.contains("claude.ai"))
    XCTAssertTrue(claude.dataSummary.contains("screenshots"))
    XCTAssertTrue(claude.dataSummary.contains("Daily Brief"))
    XCTAssertTrue(claude.dataSummary.contains("name"))
    let codex = ProviderConsentDescriptors.forCLITool(.codex)
    XCTAssertTrue(codex.destination.contains("api.openai.com"))
    XCTAssertTrue(codex.destination.contains("chatgpt.com"))
    XCTAssertTrue(codex.dataSummary.contains("screenshots"))
    XCTAssertTrue(codex.dataSummary.contains("Daily Brief"))
  }

  func testCLIDescriptorsAreToolScoped() {
    XCTAssertEqual(ProviderConsentDescriptors.forCLITool(.claude).key, "cli.claude")
    XCTAssertEqual(ProviderConsentDescriptors.forCLITool(.codex).key, "cli.codex")
    XCTAssertEqual(ProviderConsentDescriptors.forCLITool(.agy).key, "cli.agy")
  }

  func testConsentIsRememberedPerKey() {
    XCTAssertFalse(store.hasConsented(key: "cli.claude"))
    store.recordConsent(key: "cli.claude")
    XCTAssertTrue(store.hasConsented(key: "cli.claude"))
    XCTAssertFalse(store.hasConsented(key: "cli.codex"))
  }

  func testConsentRecordedInOneSuiteIsNotVisibleInAnother() {
    store.recordConsent(key: "cli.claude")
    let otherDefaults = UserDefaults(suiteName: "ProviderConsentTests.other.\(UUID().uuidString)")!
    XCTAssertFalse(ProviderConsentStore(defaults: otherDefaults).hasConsented(key: "cli.claude"))
  }

  // MARK: - Coordinator queueing

  private static let claudeDescriptor = ProviderConsentDescriptor(
    key: "cli.claude", providerName: "Claude", destination: "api.anthropic.com",
    dataSummary: "data")
  private static let codexDescriptor = ProviderConsentDescriptor(
    key: "cli.codex", providerName: "Codex", destination: "api.openai.com",
    dataSummary: "data")

  /// Approving one provider must never resume or authorize a concurrent send
  /// to another provider: each decision resumes only its own waiters.
  func testApprovalResumesOnlyTheShownProvider() async {
    let coordinator = await MainActor.run { () -> ProviderConsentCoordinator in
      let coordinator = ProviderConsentCoordinator()
      coordinator.presentHost = {}
      return coordinator
    }

    let claudeTask = Task { await coordinator.requestConsent(for: Self.claudeDescriptor) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    let codexTask = Task { await coordinator.requestConsent(for: Self.codexDescriptor) }
    try? await Task.sleep(nanoseconds: 50_000_000)

    var pending = await coordinator.pendingDescriptor
    XCTAssertEqual(pending?.key, "cli.claude")

    await coordinator.respond(true)
    let claudeAllowed = await claudeTask.value
    XCTAssertTrue(claudeAllowed)

    // Codex was not resumed by Claude's approval: it is still waiting on its
    // own modal, which the coordinator presents after the dismissal settles.
    try? await Task.sleep(nanoseconds: 150_000_000)
    pending = await coordinator.pendingDescriptor
    XCTAssertEqual(pending?.key, "cli.codex")

    await coordinator.respond(false)
    let codexAllowed = await codexTask.value
    XCTAssertFalse(codexAllowed)
    let isShowing = await coordinator.isShowingModal
    XCTAssertFalse(isShowing)
  }

  /// Two waits on the same provider share its single prompt.
  func testConcurrentWaitsForSameProviderShareOnePrompt() async {
    let coordinator = await MainActor.run { () -> ProviderConsentCoordinator in
      let coordinator = ProviderConsentCoordinator()
      coordinator.presentHost = {}
      return coordinator
    }

    let first = Task { await coordinator.requestConsent(for: Self.claudeDescriptor) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    let second = Task { await coordinator.requestConsent(for: Self.claudeDescriptor) }
    try? await Task.sleep(nanoseconds: 50_000_000)

    let pending = await coordinator.pendingDescriptor
    XCTAssertEqual(pending?.key, "cli.claude")

    await coordinator.respond(true)
    let firstAllowed = await first.value
    let secondAllowed = await second.value
    XCTAssertTrue(firstAllowed)
    XCTAssertTrue(secondAllowed)

    // No second modal was queued for the same provider.
    let next = await coordinator.pendingDescriptor
    XCTAssertNil(next)
    let isShowing = await coordinator.isShowingModal
    XCTAssertFalse(isShowing)
  }
}
