import XCTest

@testable import Dayflow

final class LocalChatLoopTests: XCTestCase {
  private func request(_ tool: String, date: String) -> ChatToolRequest {
    ChatToolRequest(tool: tool, date: date, startDate: nil, endDate: nil)
  }

  private func result(_ data: String) -> ChatToolResult {
    ChatToolResult(
      tool: .fetchTimeline, success: true, summary: "1 card", dataForLLM: data, itemCount: 1)
  }

  /// Parses only the test's tool-call marker, so the loop is tested without the app's JSON parser.
  private func parse(_ text: String) -> ChatToolRequest? {
    text.hasPrefix("CALL ") ? request("fetchTimeline", date: String(text.dropFirst(5))) : nil
  }

  func testPlainAnswerCompletesWithoutRunningTools() async throws {
    var events: [ChatStreamEvent] = []
    var toolRuns = 0
    let loop = LocalChatLoop(
      complete: { _ in "Hi there" },
      parseToolCall: parse,
      runTool: { _ in
        toolRuns += 1
        return self.result("")
      }
    )

    try await loop.run(systemInstruction: "sys", history: [.user("hello")]) { events.append($0) }

    XCTAssertEqual(toolRuns, 0)
    guard case .complete(let text)? = events.first, events.count == 1 else {
      return XCTFail("expected one complete event, got \(events)")
    }
    XCTAssertEqual(text, "Hi there")
  }

  func testToolCallResultIsFedBackBeforeTheAnswer() async throws {
    var events: [ChatStreamEvent] = []
    var seenByModel: [[LocalChatLoop.Message]] = []
    var replies = ["CALL 2026-10-20", "Tuesday was busiest."]
    let loop = LocalChatLoop(
      complete: { messages in
        seenByModel.append(messages)
        return replies.removeFirst()
      },
      parseToolCall: parse,
      runTool: { _ in self.result("09:00 Coding") }
    )

    try await loop.run(systemInstruction: "sys", history: [.user("when was I busy?")]) {
      events.append($0)
    }

    XCTAssertEqual(seenByModel.count, 2)
    XCTAssertEqual(seenByModel[0].first, LocalChatLoop.Message(role: "system", text: "sys"))
    XCTAssertTrue(seenByModel[1].contains(LocalChatLoop.Message(role: "user", text: "Tool result:\n09:00 Coding")))
    XCTAssertEqual(events.count, 3)
    guard case .toolStart? = events.first, case .toolEnd? = events.dropFirst().first,
      case .complete(let text)? = events.last
    else { return XCTFail("unexpected events \(events)") }
    XCTAssertEqual(text, "Tuesday was busiest.")
  }

  func testStopsWithAnErrorWhenTheModelKeepsCallingTools() async throws {
    var events: [ChatStreamEvent] = []
    var calls = 0
    let loop = LocalChatLoop(
      complete: { _ in
        calls += 1
        return "CALL 2026-10-20"
      },
      parseToolCall: parse,
      runTool: { _ in self.result("data") }
    )

    try await loop.run(systemInstruction: "sys", history: [.user("loop")]) { events.append($0) }

    XCTAssertEqual(calls, LocalChatLoop.maxToolRounds)
    guard case .error? = events.last else { return XCTFail("expected error, got \(events)") }
  }
}

final class OpenAICompatibleChatRequestTests: XCTestCase {
  func testChatRequestKeepsRolesAndOrder() throws {
    let provider = OpenAICompatibleProvider(
      configuration: .init(
        configuration: .init(preset: .custom, baseURL: "http://studio.local:8443", modelID: "gemma4-vision"),
        bearerToken: nil))
    let request = provider.makeChatRequest(messages: [
      .init(role: "system", text: "be brief"),
      .init(role: "user", text: "hi"),
      .init(role: "assistant", text: "hello"),
      .init(role: "user", text: "again"),
    ])

    XCTAssertEqual(request.model, "gemma4-vision")
    XCTAssertEqual(request.messages.map(\.role), ["system", "user", "assistant", "user"])
    XCTAssertEqual(request.messages.last?.content.first?.text, "again")
    XCTAssertNil(request.reasoning)
  }
}
