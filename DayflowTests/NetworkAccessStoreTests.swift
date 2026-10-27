//
//  NetworkAccessStoreTests.swift
//  DayflowTests
//
//  Dayflow is local-first: the network scope defaults to `localhostOnly` and can
//  only be widened by the user's explicit choice.
//

import XCTest
@testable import Dayflow

final class NetworkAccessStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var store: NetworkAccessStore!

  override func setUp() {
    super.setUp()
    // Isolated suite so tests never leak into the real UserDefaults.standard.
    defaults = UserDefaults(suiteName: "test.NetworkAccessStore")!
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkAccessStore")
    store = NetworkAccessStore(defaults: defaults)
  }

  override func tearDown() {
    store.setScope(.localhostOnly)
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkAccessStore")
    store = nil
    defaults = nil
    super.tearDown()
  }

  func testDefaultsToLocalhostOnly() {
    // Local-first: permission starts at "This Mac only".
    XCTAssertEqual(store.scope, .localhostOnly)
  }

  func testSetScopePersists() {
    store.setScope(.anyNetwork)
    XCTAssertEqual(store.scope, .anyNetwork)
  }

  func testScopeCanBeNarrowedBack() {
    store.setScope(.anyNetwork)
    store.setScope(.localhostOnly)
    XCTAssertEqual(store.scope, .localhostOnly)
  }

  func testScopeSurvivesReRead() {
    store.setScope(.localNetwork)
    let freshStore = NetworkAccessStore(defaults: defaults)
    XCTAssertEqual(freshStore.scope, .localNetwork)
  }

  func testSharedIsSingleton() {
    XCTAssertTrue(NetworkAccessStore.shared === NetworkAccessStore.shared)
  }
}
