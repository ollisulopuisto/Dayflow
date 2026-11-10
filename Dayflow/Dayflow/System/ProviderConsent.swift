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

import AppKit
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

  /// The Daily Brief docket handoff uses the provider's CLI when it is
  /// installed and falls back to a prefilled web URL otherwise, so its prompt
  /// names both destinations. It shares the provider's consent key: asking
  /// once per provider still holds across all send paths.
  static func forDocketHandoff(_ tool: ChatCLITool) -> ProviderConsentDescriptor {
    let base = forCLITool(tool)
    let destination: String
    switch tool {
    case .claude:
      destination = "claude.ai or api.anthropic.com"
    case .codex:
      destination = "chatgpt.com or api.openai.com"
    case .agy:
      destination = base.destination
    }
    return ProviderConsentDescriptor(
      key: base.key,
      providerName: base.providerName,
      destination: destination,
      dataSummary: String(localized: "the task title and notes from your Daily Brief")
    )
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
      // The endpoint already carries its scheme, so parse it directly and only
      // add one when missing.
      if let endpoint = DayflowBackendConfiguration.endpoint(),
        let endpointHost = URL(
          string: endpoint.contains("://") ? endpoint : "https://\(endpoint)")?.host?
          .lowercased(),
        endpointHost == host
      {
        providerName = String(localized: "Dayflow Cloud")
      } else {
        providerName = String(localized: "your OpenAI-compatible endpoint")
      }
    }
    // A non-default port is part of the destination: pointing the same host at
    // a different port is a different service, so it asks again.
    let schemeDefaultPort = url.scheme == "https" ? 443 : 80
    let portSuffix: String
    if let port = url.port, port != schemeDefaultPort {
      portSuffix = ":\(port)"
    } else {
      portSuffix = ""
    }
    return ProviderConsentDescriptor(
      key: "http.\(host)\(portSuffix)",
      providerName: providerName,
      destination: "\(host)\(portSuffix)",
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

  /// Brings the app forward so the modal is seen even when Dayflow launched in
  /// the background without a main window. Tests replace it with a no-op.
  var presentHost: @MainActor () -> Void = {
    NSApp.activate(ignoringOtherApps: true)
    MainWindowController.shared.showMainWindow()
  }

  /// Providers waiting for their turn, first in the queue is on screen.
  private var queue: [ProviderConsentDescriptor] = []
  /// Waiting consent checks, grouped by descriptor key so a decision resumes
  /// only the waiters for the provider it named - never another provider's.
  private var waiters: [String: [CheckedContinuation<Bool, Never>]] = [:]
  /// Set while a presentation hop is enqueued, so requests coalesce.
  private var presentationScheduled = false

  /// Internal rather than private so tests can exercise the queueing.
  init() {}

  /// Shows the consent modal for `descriptor` and waits for its decision.
  /// Returns `true` only if the user taps "Allow" for this provider. Requests
  /// for other providers queue behind the current modal and keep waiting; a
  /// declined descriptor simply asks again on its next send.
  func requestConsent(for descriptor: ProviderConsentDescriptor) async -> Bool {
    if !queue.contains(where: { $0.key == descriptor.key }) {
      queue.append(descriptor)
    }
    schedulePresentation()
    return await withCheckedContinuation { continuation in
      waiters[descriptor.key, default: []].append(continuation)
    }
  }

  /// Dismisses the current modal, resumes only the checks waiting on the
  /// provider it named, and queues the next provider's modal, if any.
  func respond(_ allowed: Bool) {
    guard let descriptor = pendingDescriptor else { return }
    queue.removeAll { $0.key == descriptor.key }
    pendingDescriptor = nil
    isShowingModal = false
    let waitingRequests = waiters.removeValue(forKey: descriptor.key) ?? []
    waitingRequests.forEach { $0.resume(returning: allowed) }
    schedulePresentation()
  }

  /// Presents one runloop turn later. SwiftUI must observe the alert binding
  /// go false and finish dismissing before it goes true again; flipping it in
  /// the same turn can swallow the transition, and a queued provider's send
  /// would wait on an alert that never appears.
  private func schedulePresentation() {
    guard !presentationScheduled else { return }
    presentationScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.presentationScheduled = false
      self.presentNext()
    }
  }

  private func presentNext() {
    guard pendingDescriptor == nil, let next = queue.first else { return }
    pendingDescriptor = next
    isShowingModal = true
    presentHost()
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
