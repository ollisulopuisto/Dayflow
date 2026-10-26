//
//  NetworkAccessCoordinator.swift
//  Dayflow
//
//  @MainActor coordinator that bridges `NetworkGate`'s async authorization with
//  SwiftUI modal state. When `NetworkGate` needs a wider access scope it
//  calls `requestAccess(for:)`, which shows the modal alarm and suspends until
//  the user explicitly taps "Allow" or "Don't Allow".
 //

import Foundation
import SwiftUI

/// Presents the network-scope modal alarm and suspends the calling
/// `NetworkGate.allow(_:)` until the user explicitly grants or denies permission.
@MainActor
final class NetworkAccessCoordinator: ObservableObject {
  static let shared = NetworkAccessCoordinator()

  /// Whether the modal alarm is currently on screen.
  @Published private(set) var isShowingModal = false
  /// The URL that triggered the modal, shown to the user for transparency.
  @Published private(set) var pendingURL: URL?
  /// Minimum access scope needed for the pending request.
  @Published private(set) var pendingScope: NetworkAccessScope = .anyNetwork

  private var continuations: [CheckedContinuation<Bool, Never>] = []

  private init() {}

  /// Show the modal alarm for `url` and wait for the user's explicit decision.
  /// Returns `true` only if the user taps "Allow".
  func requestAccess(for url: URL) async -> Bool {
    let requiredScope = NetworkAccessScope.required(for: url)
    if !isShowingModal {
      pendingURL = url
      pendingScope = requiredScope
      isShowingModal = true
    } else if requiredScope.rank > pendingScope.rank {
      pendingURL = url
      pendingScope = requiredScope
    }
    return await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  /// Dismiss the modal and resume the waiting `NetworkGate.allow(_:)` with `allowed`.
  func respond(_ allowed: Bool) {
    isShowingModal = false
    pendingURL = nil
    let waitingRequests = continuations
    continuations.removeAll()
    waitingRequests.forEach { $0.resume(returning: allowed) }
  }
}
