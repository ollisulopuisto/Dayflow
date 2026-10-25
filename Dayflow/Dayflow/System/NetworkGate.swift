//
//  NetworkGate.swift
//  Dayflow
//
//  Central choke point for all outside (non-localhost) network access.
//  Dayflow is local-first: by default NO outside network access is allowed.
//  Every request is funneled through `allow(_:)`, which returns `false` unless
//  the user has explicitly granted permission via the modal alarm in
//  `NetworkAccessModalView`.
//
//  A `NetworkBlockingURLProtocol` is registered process-wide as a backstop so
//  even third-party SDKs (analytics, updater, etc.) cannot reach the outside
//  network unless permission has been granted.
//

import Foundation

/// Decision engine: is a given URL allowed to make a network request?
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

  /// Returns `true` iff the request to `url` may proceed over the network.
  ///
  /// - Localhost/link-local and `file://` URLs are local access: always allowed.
  /// - Outside network is blocked by default until `authorize` returns `true`,
  ///   at which point permission is persisted and all subsequent requests pass.
  func allow(_ url: URL) async -> Bool {
    if isLocalHost(url) { return true }
    if store.isAllowed { return true }
    lock.lock()
    let authorizer = authorize
    lock.unlock()
    guard let authorizer else { return false }
    let allowed = await authorizer(url)
    if allowed { store.setAllowed(true) }
    return allowed
  }

  private func isLocalHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return true } // file:// etc. -> local
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}
