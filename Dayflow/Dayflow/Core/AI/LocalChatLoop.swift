import Foundation

/// Runs one chat turn for a local model that has no native tool calling.
///
/// The model asks for data by replying with a JSON tool call (see `ChatToolExecutor`).
/// The result is fed back as a user message, and the loop stops at the first plain-text reply.
extension LocalChatLoop {
  @MainActor
  static func systemPrompt(now: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return """
      You are Dayflow's assistant. Dayflow records the user's screen and summarizes it into activity cards.
      Answer questions about the user's activity using only data you fetched with a tool.
      The current date and time is \(formatter.string(from: now)).

      \(ChatToolExecutor.toolDescription)
      """
  }
}

struct LocalChatLoop {
  struct Message: Equatable {
    let role: String
    let text: String
  }

  static let maxToolRounds = 6

  let complete: ([Message]) async throws -> String
  let parseToolCall: (String) async -> ChatToolRequest?
  let runTool: (ChatToolRequest) async -> ChatToolResult

  func run(
    systemInstruction: String,
    history: [DashboardChatTurn],
    emit: (ChatStreamEvent) -> Void
  ) async throws {
    var messages = [Message(role: "system", text: systemInstruction)]
    messages += history.map { Message(role: $0.role.rawValue, text: $0.content) }

    for _ in 0..<Self.maxToolRounds {
      let output = try await complete(messages)
      guard let call = await parseToolCall(output) else {
        emit(.complete(text: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        return
      }

      let label = [call.tool, call.date].compactMap { $0 }.joined(separator: " ")
      emit(.toolStart(command: label))
      let result = await runTool(call)
      emit(.toolEnd(output: result.summary, exitCode: result.success ? 0 : 1))

      messages.append(Message(role: "assistant", text: output))
      messages.append(Message(role: "user", text: "Tool result:\n" + result.dataForLLM))
    }

    emit(.error("The local model kept asking for data. Try a narrower question."))
  }
}
