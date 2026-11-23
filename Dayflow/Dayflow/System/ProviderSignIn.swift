//
//  ProviderSignIn.swift
//  Dayflow
//
//  Signs the user back in to Claude or ChatGPT from inside Dayflow. It runs the tool's own
//  login command in the background, which opens the browser, then checks that the sign-in
//  worked and retries the batches that were waiting.
//

import Foundation

@MainActor
final class ProviderSignIn: ObservableObject {
  enum State: Equatable {
    case idle
    case waiting(LLMProviderID)
    case failed(LLMProviderID)
  }

  static let shared = ProviderSignIn()

  @Published private(set) var state: State = .idle

  /// True when the last attempt failed because Dayflow couldn't find the provider's
  /// command-line tool on this Mac, so trying again or using Terminal won't help.
  @Published private(set) var toolIsMissing = false

  private var process: Process?
  private var input: Pipe?
  private var watchTask: Task<Void, Never>?

  private static let timeout: TimeInterval = 10 * 60
  private static let checkInterval: Duration = .seconds(3)

  nonisolated static func displayName(for provider: LLMProviderID) -> String {
    provider == .claude ? "Claude" : "ChatGPT"
  }

  /// Opens the browser sign-in for `provider`. Calling it again restarts the sign-in, which is
  /// what "Browser didn't open? Try again" does.
  func start(_ provider: LLMProviderID, source: String) {
    AnalyticsService.shared.capture(
      "provider_sign_in_started", ["provider_id": provider.rawValue, "source": source])

    guard let command = Self.loginCommand(for: provider) else {
      stopProcess()
      toolIsMissing = true
      AnalyticsService.shared.capture(
        "provider_sign_in_finished",
        ["provider_id": provider.rawValue, "succeeded": false, "reason": "tool_not_found"])
      state = .failed(provider)
      return
    }
    stopProcess()
    toolIsMissing = false

    state = .waiting(provider)
    watchTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await ProviderConsentGate.requireCLI(provider == .claude ? .claude : .codex)
        guard !Task.isCancelled else { return }
        launch(command, provider: provider)
      } catch {
        guard !Task.isCancelled else { return }
        finish(provider, succeeded: false, reason: "consent_declined")
      }
    }
  }

  private func launch(_ command: String, provider: LLMProviderID) {
    let process = ShellEnvironment.shared.makeProcess(command: command)
    // The tool only needs to open the browser and wait. An open, silent input keeps it from
    // quitting early because it thinks the terminal went away.
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      finish(provider, succeeded: false, reason: "launch_failed")
      return
    }

    self.process = process
    self.input = input
    state = .waiting(provider)
    watchTask = Task { [weak self] in
      await self?.watch(process, provider: provider)
    }
  }
