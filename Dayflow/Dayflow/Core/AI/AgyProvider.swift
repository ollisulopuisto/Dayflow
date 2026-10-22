import Foundation

/// Antigravity CLI (`agy`) as a Dashboard Chat backend.
final class AgyProvider {
  let runner = ChatCLIProcessRunner()
  let config = ChatCLIConfigManager.shared

  init() {
    config.ensureWorkingDirectory()
  }

  func generateChatStreaming(prompt: String, sessionId: String? = nil) -> AsyncThrowingStream<
    ChatStreamEvent, Error
  > {
    runner.runStreaming(
      tool: .agy,
      prompt: prompt,
      workingDirectory: config.workingDirectory,
      sessionId: sessionId
    )
  }
}
