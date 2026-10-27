//
//  NetworkGateTests.swift
//  DayflowTests
//
//  NetworkGate is the central deny-by-default choke point for outside network
//  access. Localhost is always allowed; everything else is blocked until the
//  user explicitly authorizes it via the modal alarm.
//

import XCTest
@testable import Dayflow

final class NetworkGateTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: NetworkAccessStore!
  private var gate: NetworkGate!

  override func setUp() {
    super.setUp()
    suiteName = "test.NetworkGate.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    store = NetworkAccessStore(defaults: defaults)
    gate = NetworkGate(store: store)
  }

  override func tearDown() {
    store.setScope(.localhostOnly)
    defaults.removePersistentDomain(forName: suiteName)
    gate = nil
    store = nil
    defaults = nil
    super.tearDown()
  }

  func testPublicInternetBlockedByDefault() async {
    gate.setAuthorize { _ in false }
    let allowed = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertFalse(allowed)
    XCTAssertEqual(store.scope, .localhostOnly)
  }

  func testDeniedAuthorizerKeepsScopeLocal() async {
    gate.setAuthorize { _ in false }
    let allowed = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertFalse(allowed)
    XCTAssertEqual(store.scope, .localhostOnly)
  }

  func testExplicitAuthorizationAllowsAndPersists() async {
    var received: [URL] = []
    gate.setAuthorize { url in
      received.append(url)
      return true
    }

    let url = URL(string: "https://example.com")!
    let allowed = await gate.allow(url)
    XCTAssertTrue(allowed)
    XCTAssertEqual(store.scope, .anyNetwork, "permission should be widened after explicit grant")
    XCTAssertEqual(received.count, 1, "authorizer should be invoked once")
    XCTAssertEqual(received.first, url, "authorizer should receive the requested URL")
  }

  func testDenyDoesNotStorePermission() async {
    gate.setAuthorize { _ in false }

    let allowed = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertFalse(allowed)
    XCTAssertEqual(store.scope, .localhostOnly)
  }

  func testSubsequentRequestsDoNotRepromptOncePermitted() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    _ = await gate.allow(URL(string: "https://example.com")!)
    let firstAllowed = await gate.allow(URL(string: "https://example.org")!)
    XCTAssertTrue(firstAllowed)
    let secondAllowed = await gate.allow(URL(string: "https://example.net")!)
    XCTAssertTrue(secondAllowed)
    XCTAssertEqual(promptCount, 1, "authorizer should only run once after permission granted")
    XCTAssertEqual(store.scope, .anyNetwork)
  }

  func testLocalhostAlwaysAllowedWithoutPrompt() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    let firstAllowed = await gate.allow(URL(string: "http://127.0.0.1:9876/")!)
    XCTAssertTrue(firstAllowed)
    let secondAllowed = await gate.allow(URL(string: "http://localhost:9876/")!)
    XCTAssertTrue(secondAllowed)
    let thirdAllowed = await gate.allow(URL(string: "http://[::1]:9876/")!)
    XCTAssertTrue(thirdAllowed)
    XCTAssertEqual(promptCount, 0, "localhost must never prompt")
    XCTAssertEqual(store.scope, .localhostOnly, "localhost should not widen the scope")
  }

  func testFileURLsTreatedAsLocal() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    let allowed = await gate.allow(URL(string: "file:///tmp/foo.txt")!)
    XCTAssertTrue(allowed)
    XCTAssertEqual(promptCount, 0, "file URLs must never prompt")
  }

  func testResetReBlocksPublicInternet() async {
    gate.setAuthorize { _ in true }
    _ = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertEqual(store.scope, .anyNetwork)

    store.setScope(.localhostOnly)
    let freshGate = NetworkGate(store: store)
    freshGate.setAuthorize { _ in false }
    let allowed = await freshGate.allow(URL(string: "https://example.com")!)
    XCTAssertFalse(allowed)
  }
}
