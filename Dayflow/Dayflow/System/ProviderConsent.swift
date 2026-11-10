//
//  ProviderConsent.swift
//  Dayflow
//
//  One-time, per-provider consent before Dayflow first sends data to an
//  external AI provider. HTTP providers are gated in LLMURLSession (plus the
//  few direct URLSession call sites); CLI providers (Claude, Codex, agy) are
//  gated in ChatCLIProcessRunner because their subprocesses talk to the
//  network directly and bypass NetworkGate.
//
//  Consent is remembered per provider once allowed. Declining sends nothing,
//  and the prompt returns on the next attempt.
//

import Foundation
import SwiftUI

/// What the consent modal names: who receives the data, where it goes, and
/// what is sent.
struct ProviderConsentDescriptor: Equatable {
  /// Stable key the remembered consent is stored under (tool- or host-scoped).
  let key: String
  let providerName: String
  let destination: String
  let dataSummary: String
}

enum ProviderConsentError: LocalizedError {
  case declined(String)

  var errorDescription: String? {
    switch self {
    case .declined(let providerName):
      return String(
        localized:
          "Dayflow did not send anything to \(providerName). Allow it when asked to use this provider."
        )
    }
  }
}

enum ProviderConsentDescriptors {
  private static let screenDataSummary = String(
    localized: "screenshots of your screen, text extracted from them, and your prompts")

  static func forCLITool(_ tool: ChatCLITool) -> ProviderConsentDescriptor {
    switch tool {
    case .claude:
      return ProviderConsentDescriptor(
        key: "cli.claude",
        providerName: String(localized: "Claude (Anthropic)"),
        destination: "api.anthropic.com",
        dataSummary: screenDataSummary
      )
    case .codex:
      return ProviderConsentDescriptor(
        key: "cli.codex",
        providerName: String(localized: "Codex / ChatGPT (OpenAI)"),
        destination: "api.openai.com",
        dataSummary: screenDataSummary
      )
    case .agy:
      return ProviderConsentDescriptor(
        key: "cli.agy",
        providerName: String(localized: "Antigravity (Google)"),
        destination: String(localized: "Google's API"),
        dataSummary: String(localized: "your chat prompts")
      )
    }
  }

  /// Consent descriptor for an AI provider reached over HTTP, or nil when the
  /// host is this Mac or the local network - those connections ask through the
  /// network access scope instead.
  static func forHTTPURL(_ url: URL?) -> ProviderConsentDescriptor? {
    guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return nil }
    guard NetworkAccessScope.required(for: url) == .anyNetwork else { return nil }

    let providerName: String
    switch host {
    case "generativelanguage.googleapis.com":
      providerName = String(localized: "Google Gemini API")
    case "api.openrouter.ai":
      providerName = "OpenRouter"
    case "api.requesty.ai":
      providerName = "Requesty"
    case "api.siliconflow.cn":
      providerName = "SiliconFlow"
    default:
      if let endpoint = DayflowBackendConfiguration.endpoint(),
        let endpointHost = URL(string: "https://\(endpoint)")?.host?.lowercased(),
        endpointHost == host
      {
        providerName = String(localized: "Dayflow Cloud")
      } else {
        providerName = String(localized: "your OpenAI-compatible endpoint")
      }
    }
    return ProviderConsentDescriptor(
      key: "http.\(host)",
      providerName: providerName,
      destination: host,
      dataSummary: screenDataSummary
    )
  }
}

/// Remembers per-provider consent in UserDefaults.
final class ProviderConsentStore {
  static let shared = ProviderConsentStore()

  private static let keyPrefix = "providerConsent."
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func hasConsented(key: String) -> Bool {
    defaults.bool(forKey: Self.keyPrefix + key)
  }

  func recordConsent(key: String) {
    defaults.set(true, forKey: Self.keyPrefix + key)
    defaults.set(Date().timeIntervalSince1970, forKey: Self.keyPrefix + key + ".date")
  }
}

/// Bridges the async consent check with SwiftUI modal state. When a provider
/// has no remembered consent, `requestConsent(for:)` shows the modal and
/// suspends until the user taps "Allow" or "Don't Send".
@MainActor
final class ProviderConsentCoordinator: ObservableObject {
  static let shared = ProviderConsentCoordinator()

  /// Whether the consent modal is currently on screen.
  @Published private(set) var isShowingModal = false
  /// The provider awaiting a decision, named in the modal.
  @Published private(set) var pendingDescriptor: ProviderConsentDescriptor?

  private var continuations: [CheckedContinuation<Bool, Never>] = []

  private init() {}

  /// Shows the consent modal for `descriptor` and waits for the decision.
  /// Returns `true` only if the user taps "Allow". Concurrent requests share
  /// the one modal; a declined descriptor simply asks again on its next send.
  func requestConsent(for descriptor: ProviderConsentDescriptor) async -> Bool {
    if !isShowingModal {
      pendingDescriptor = descriptor
      isShowingModal = true
    }
    return await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  /// Dismisses the modal and resumes the waiting consent checks.
  func respond(_ allowed: Bool) {
    isShowingModal = false
    pendingDescriptor = nil
    let waitingRequests = continuations
    continuations.removeAll()
    waitingRequests.forEach { $0.resume(returning: allowed) }
  }
}

enum ProviderConsentGate {
  /// Prompts when this provider has no remembered consent, remembers an
  /// "Allow", and throws when the user declines. Sends nothing before "Allow".
  static func require(_ descriptor: ProviderConsentDescriptor) async throws {
    if ProviderConsentStore.shared.hasConsented(key: descriptor.key) { return }
    let allowed = await ProviderConsentCoordinator.shared.requestConsent(for: descriptor)
    guard allowed else { throw ProviderConsentError.declined(descriptor.providerName) }
    ProviderConsentStore.shared.recordConsent(key: descriptor.key)
  }

  static func requireCLI(_ tool: ChatCLITool) async throws {
    try await require(ProviderConsentDescriptors.forCLITool(tool))
  }

  /// No-op for hosts on this Mac or the local network.
  static func requireHTTP(_ url: URL?) async throws {
    guard let descriptor = ProviderConsentDescriptors.forHTTPURL(url) else { return }
    try await require(descriptor)
  }

  /// Synchronous fail-safe for send paths that cannot prompt (blocking CLI
  /// runs). The async gates prompt first, so reaching this throw means a call
  /// path missed its prompt - it never sends without remembered consent.
  static func requireConsentedCLI(_ tool: ChatCLITool) throws {
    let descriptor = ProviderConsentDescriptors.forCLITool(tool)
    guard ProviderConsentStore.shared.hasConsented(key: descriptor.key) else {
      throw ProviderConsentError.declined(descriptor.providerName)
    }
  }
}
