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
    XCTAssertFalse(descriptor?.dataSummary.isEmpty ?? true)
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
}
