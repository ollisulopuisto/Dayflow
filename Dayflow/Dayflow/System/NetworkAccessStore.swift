//
//  NetworkAccessStore.swift
//  Dayflow
//
//  Persists the user's explicit outside-network permission.
//  Dayflow is local-first: by default NO outside network access is allowed.
//  The permission defaults to `false` and can only be flipped to `true` through
//  the explicit modal alarm in `NetworkAccessModalView`.
 //

import Foundation

/// Single source of truth for whether outside (non-localhost) network access is allowed.
///
/// Defaults to `false` (local-only). Persisted in UserDefaults so the choice
/// survives relaunches. Thin wrapper around `UserDefaults`, which is internally
/// synchronized, so all accessors are safe to call from any thread/actor.
final class NetworkAccessStore {
  static let shared = NetworkAccessStore()

  private let defaults: UserDefaults
  private let key = "networkAccessAllowed"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// `true` only after the user has explicitly granted outside-network permission.
  var isAllowed: Bool {
    defaults.bool(forKey: key)
  }

  /// Record the user's explicit choice.
  func setAllowed(_ value: Bool) {
    defaults.set(value, forKey: key)
  }

  /// Revoke permission and return to the local-only default.
  func reset() {
    defaults.removeObject(forKey: key)
  }
}
