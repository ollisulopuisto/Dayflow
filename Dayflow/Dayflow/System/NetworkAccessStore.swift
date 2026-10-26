//
//  NetworkAccessStore.swift
//  Dayflow
//
//  Persists the user's network access scope. macOS's Local Network permission
//  remains a separate system-level allow/deny decision.
//

import Foundation

enum NetworkAccessScope: String, CaseIterable, Identifiable, Equatable, Sendable {
  case localhostOnly
  case localNetwork
  case anyNetwork

  var id: String { rawValue }

  var rank: Int {
    switch self {
    case .localhostOnly: return 0
    case .localNetwork: return 1
    case .anyNetwork: return 2
    }
  }

  var title: String {
    switch self {
    case .localhostOnly: return String(localized: "This Mac only")
    case .localNetwork: return String(localized: "Local network")
    case .anyNetwork: return String(localized: "Any network")
    }
  }

  var detail: String {
    switch self {
    case .localhostOnly:
      return String(localized: "Connect only to services running on this Mac.")
    case .localNetwork:
      return String(localized: "Connect to this Mac and devices on your local network, including your Mac Studio.")
    case .anyNetwork:
      return String(localized: "Connect to local devices and internet services, including AI providers and Dayflow services.")
    }
  }

  func allows(_ url: URL) -> Bool {
    switch self {
    case .localhostOnly:
      return Self.isLoopback(url.host)
    case .localNetwork:
      return Self.isLocalNetworkHost(url.host)
    case .anyNetwork:
      return true
    }
  }

  static func required(for url: URL) -> NetworkAccessScope {
    if isLoopback(url.host) { return .localhostOnly }
    return isLocalNetworkHost(url.host) ? .localNetwork : .anyNetwork
  }

  private static func isLoopback(_ rawHost: String?) -> Bool {
    guard let host = normalizedHost(rawHost) else { return true }
    return host == "localhost" || host.hasSuffix(".localhost")
      || host == "::1" || host == "0:0:0:0:0:0:0:1"
      || host.hasPrefix("::ffff:") && isIPv4(String(host.dropFirst(7)), matching: { $0[0] == 127 })
      || isIPv4(host, matching: { $0[0] == 127 })
  }

  private static func isLocalNetworkHost(_ rawHost: String?) -> Bool {
    guard let host = normalizedHost(rawHost) else { return true }
    if isLoopback(host) { return true }
    if host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home")
      || host.hasSuffix(".internal") || host.hasSuffix(".home.arpa") || host.hasSuffix(".ts.net")
    {
      return true
    }
    if !host.contains("."), !host.contains(":"), !host.isEmpty {
      // Common local device names such as "mac-studio" have no DNS suffix.
      return true
    }
    if isIPv4(host, matching: { octets in
      octets[0] == 10
        || (octets[0] == 172 && (16...31).contains(octets[1]))
        || (octets[0] == 192 && octets[1] == 168)
        || (octets[0] == 169 && octets[1] == 254)
        || (octets[0] == 100 && (64...127).contains(octets[1]))
    }) {
      return true
    }
    return host.contains(":")
      && (host.hasPrefix("fc") || host.hasPrefix("fd")
        || host.hasPrefix("fe8") || host.hasPrefix("fe9")
        || host.hasPrefix("fea") || host.hasPrefix("feb"))
  }

  private static func normalizedHost(_ rawHost: String?) -> String? {
    guard let rawHost else { return nil }
    let host = rawHost.lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
      .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init)
    guard let host else { return nil }
    return host.hasSuffix(".") ? String(host.dropLast()) : host
  }

  private static func isIPv4(_ host: String, matching predicate: ([Int]) -> Bool) -> Bool {
    let parts = host.split(separator: ".")
    guard parts.count == 4 else { return false }
    let octets = parts.compactMap { Int($0) }
    guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
    return predicate(octets)
  }
}

/// Persists the user's app-level network scope. It restricts Dayflow's HTTP(S)
/// requests; macOS still controls Local Network access independently.
final class NetworkAccessStore {
  static let shared = NetworkAccessStore()

  private let defaults: UserDefaults
  private let key = "networkAccessScope"
  private let legacyKey = "networkAccessAllowed"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var scope: NetworkAccessScope {
    if let rawValue = defaults.string(forKey: key),
      let stored = NetworkAccessScope(rawValue: rawValue)
    {
      return stored
    }
    // Preserve the former binary choice: granted meant unrestricted external access.
    return defaults.bool(forKey: legacyKey) ? .anyNetwork : .localhostOnly
  }

  func setScope(_ scope: NetworkAccessScope) {
    defaults.set(scope.rawValue, forKey: key)
    defaults.removeObject(forKey: legacyKey)
  }
}
