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
  private var defaults: UserDefaults!
  private var store: NetworkAccessStore!
  private var gate: NetworkGate!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "test.NetworkGate")!
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkGate")
    store = NetworkAccessStore(defaults: defaults)
    gate = NetworkGate(store: store)
  }

  override func tearDown() {
    store.reset()
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkGate")
    gate = nil
    store = nil
    defaults = nil
    super.tearDown()
  }

  func testPublicInternetBlockedByDefault() async {
    gate.setAuthorize(nil)
    XCTAssertFalse(await gate.allow(URL(string: "https://example.com")!))
  }

  func testNoAuthorizerMeansBlocked() async {
    gate.setAuthorize(nil)
    XCTAssertFalse(await gate.allow(URL(string: "https://example.com")!))
    XCTAssertFalse(store.isAllowed)
  }

  func testExplicitAuthorizationAllowsAndPersists() async {
    var received: [URL] = []
    gate.setAuthorize { url in
      received.append(url)
      return true
    }

    let url = URL(string: "https://example.com")!
    XCTAssertTrue(await gate.allow(url))
    XCTAssertTrue(store.isAllowed, "permission should be persisted after explicit grant")
    XCTAssertEqual(received.count, 1, "authorizer should be invoked once")
    XCTAssertEqual(received.first, url, "authorizer should receive the requested URL")
  }

  func testDenyDoesNotStorePermission() async {
    gate.setAuthorize { _ in false }

    XCTAssertFalse(await gate.allow(URL(string: "https://example.com")!))
    XCTAssertFalse(store.isAllowed)
  }

  func testSubsequentRequestsDoNotRepromptOncePermitted() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    _ = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertTrue(await gate.allow(URL(string: "https://example.org")!))
    XCTAssertTrue(await gate.allow(URL(string: "https://example.net")!))
    XCTAssertEqual(promptCount, 1, "authorizer should only run once after permission granted")
    XCTAssertTrue(store.isAllowed)
  }

  func testLocalhostAlwaysAllowedWithoutPrompt() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    XCTAssertTrue(await gate.allow(URL(string: "http://127.0.0.1:9876/")!))
    XCTAssertTrue(await gate.allow(URL(string: "http://localhost:9876/")!))
    XCTAssertTrue(await gate.allow(URL(string: "http://[::1]:9876/")!))
    XCTAssertEqual(promptCount, 0, "localhost must never prompt")
    XCTAssertFalse(store.isAllowed, "localhost should not flip the permission flag")
  }

  func testFileURLsTreatedAsLocal() async {
    var promptCount = 0
    gate.setAuthorize { _ in
      promptCount += 1
      return true
    }

    XCTAssertTrue(await gate.allow(URL(string: "file:///tmp/foo.txt")!))
    XCTAssertEqual(promptCount, 0, "file URLs must never prompt")
  }

  func testResetReBlocksPublicInternet() async {
    gate.setAuthorize { _ in true }
    _ = await gate.allow(URL(string: "https://example.com")!)
    XCTAssertTrue(store.isAllowed)

    store.reset()
    let freshGate = NetworkGate(store: store)
    freshGate.setAuthorize(nil)
    XCTAssertFalse(await freshGate.allow(URL(string: "https://example.com")!))
  }
}
