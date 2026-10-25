//
//  NetworkAccessStoreTests.swift
//  DayflowTests
//
//  Dayflow is local-first: outside-network permission defaults to `false` and can
//  only be flipped to `true` by the user's explicit choice.
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
    store.reset()
    defaults.removePersistentDomain(forName: defaults.suiteName ?? "test.NetworkAccessStore")
    store = nil
    defaults = nil
    super.tearDown()
  }

  func testDefaultsToNotAllowed() {
    // Local-first: permission starts off.
    XCTAssertFalse(store.isAllowed)
  }

  func testSetAllowedTruePersists() {
    store.setAllowed(true)
    XCTAssertTrue(store.isAllowed)
  }

  func testSetAllowedFalsePersists() {
    store.setAllowed(true)
    store.setAllowed(false)
    XCTAssertFalse(store.isAllowed)
  }

  func testResetReturnsToDefaultFalse() {
    store.setAllowed(true)
    store.reset()
    XCTAssertFalse(store.isAllowed)
  }

  func testSharedIsSingleton() {
    XCTAssertTrue(NetworkAccessStore.shared === NetworkAccessStore.shared)
  }
}
