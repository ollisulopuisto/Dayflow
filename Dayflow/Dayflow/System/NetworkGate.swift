//
//  NetworkGate.swift
//  Dayflow
//
//  Central policy for Dayflow's localhost, local-network, and internet scopes.
//  Requests that exceed the selected scope ask the user before continuing.
//
//  A `NetworkBlockingURLProtocol` is registered process-wide as a backstop so
//  even third-party SDKs (analytics, updater, etc.) cannot exceed the selected
//  scope for HTTP(S) requests.
//

import Foundation

/// Decision engine: does the selected scope allow a URL to make a connection?
final class NetworkGate {
  static let shared = NetworkGate()

  private let store: NetworkAccessStore
  private let lock = NSLock()

  /// Injected authorizer: presents the modal alarm in production, a mock in tests.
  /// Returns `true` iff the user EXPLICITLY allows outside network access.
  private(set) var authorize: ((URL) async -> Bool)?

  init(store: NetworkAccessStore = .shared) {
    self.store = store
    // Default authorizer: the modal alarm. Tests override via setAuthorize(_:).
    authorize = { [coordinator = NetworkAccessCoordinator.shared] url in
      await coordinator.requestAccess(for: url)
    }
  }

  /// Override the authorizer (production uses the modal alarm default; tests inject a mock).
  func setAuthorize(_ handler: @escaping (URL) async -> Bool) {
    lock.lock(); authorize = handler; lock.unlock()
  }

  /// Returns `true` iff the selected scope allows the request. If the request
  /// needs a wider scope, ask once and persist the scope the user approves.
  func allow(_ url: URL) async -> Bool {
    let requiredScope = NetworkAccessScope.required(for: url)
    if store.scope.allows(url) { return true }
    lock.lock()
    let authorizer = authorize
    lock.unlock()
    guard let authorizer else { return false }
    let allowed = await authorizer(url)
    if allowed, store.scope.rank < requiredScope.rank {
      store.setScope(requiredScope)
    }
    return allowed
  }
}
