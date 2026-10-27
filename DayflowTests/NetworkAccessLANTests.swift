//
//  NetworkAccessLANTests.swift
//  DayflowTests
//
//  Verifies that when the user selects "Local network" scope, Dayflow can
//  reach LAN hosts but cannot reach the public internet.
//
//
// NOTE: xcodebuild is unavailable in this environment (only command-line
// tools, no Xcode), so these tests cannot be compiled/run here. Add them to
// DayflowTests and run in Xcode.

import XCTest
@testable import Dayflow

final class NetworkAccessLANTests: XCTestCase {
  private var defaults: UserDefaults!
  private var store: NetworkAccessStore!
  private var gate: NetworkGate!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "test.NetworkAccessLAN")!
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkAccessLAN")
    store = NetworkAccessStore(defaults: defaults)
    gate = NetworkGate(store: store)
  }

  override func tearDown() {
    store.setScope(.localhostOnly)
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkAccessLAN")
    gate = nil
    store = nil
    defaults = nil
    super.tearDown()
  }

  // MARK: - NetworkAccessScope.allows()

  func testLocalNetworkScopeAllowsLAN() {
    store.setScope(.localNetwork)
    XCTAssertTrue(store.scope.allows(URL(string: "http://192.168.1.50:8080/")!))
    XCTAssertTrue(store.scope.allows(URL(string: "http://mac-studio.local/")!))
    XCTAssertTrue(store.scope.allows(URL(string: "http://10.0.0.9/")!))
  }

  func testLocalNetworkScopeBlocksPublicInternet() {
    store.setScope(.localNetwork)
    XCTAssertFalse(store.scope.allows(URL(string: "https://example.com")!))
    XCTAssertFalse(store.scope.allows(URL(string: "https://api.anthropic.com")!))
  }

  func testLocalNetworkScopeAllowsLoopback() {
    store.setScope(.localNetwork)
    XCTAssertTrue(store.scope.allows(URL(string: "http://127.0.0.1:9876/")!))
    XCTAssertTrue(store.scope.allows(URL(string: "http://localhost:9876/")!))
  }

  func testLocalhostOnlyBlocksLAN() {
    store.setScope(.localhostOnly)
    XCTAssertFalse(store.scope.allows(URL(string: "http://192.168.1.50:8080/")!))
    XCTAssertFalse(store.scope.allows(URL(string: "http://mac-studio.local/")!))
  }

  func testAnyNetworkAllowsEverything() {
    store.setScope(.anyNetwork)
    XCTAssertTrue(store.scope.allows(URL(string: "https://example.com")!))
    XCTAssertTrue(store.scope.allows(URL(string: "http://192.168.1.50:8080/")!))
  }

  // MARK: - NetworkGate.allow() with LAN scope (deny-by-default authorizer)

  func testLANScopePublicInternetBlockedWithoutAuthorizer() {
    store.setScope(.localNetwork)
    gate.setAuthorize(nil)
    XCTAssertFalse(await gate.allow(URL(string: "https://example.com")!))
  }

  func testLANScopeLANAllowedWithoutPrompt() {
    store.setScope(.localNetwork)
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }
    XCTAssertTrue(await gate.allow(URL(string: "http://192.168.1.50:8080/")!))
    XCTAssertEqual(promptCount, 0, "LAN hosts must not prompt")
  }
}
