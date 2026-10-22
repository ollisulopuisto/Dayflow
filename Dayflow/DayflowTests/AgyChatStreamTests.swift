import XCTest

@testable import Dayflow

final class AgyChatStreamTests: XCTestCase {
  private let runner = ChatCLIProcessRunner()

  func testInitEventStartsTheConversation() {
    let line = #"{"event":"init","conversation_id":"abc-123","init":{"cwd":"/x"}}"#
    guard case .sessionStarted(let id)? = runner.parseJSONLLine(tool: .agy, line: line) else {
      return XCTFail("expected sessionStarted")
    }
    XCTAssertEqual(id, "abc-123")
  }

  func testActiveAgentStepStreamsItsTextDelta() {
    let line =
      #"{"event":"step_update","step_update":{"conversation_id":"abc","step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"ping"}}"#
    guard case .textDelta(let text)? = runner.parseJSONLLine(tool: .agy, line: line) else {
      return XCTFail("expected textDelta")
    }
    XCTAssertEqual(text, "ping")
  }

  func testDoneStepDoesNotRepeatItsText() {
    let line =
      #"{"event":"step_update","step_update":{"conversation_id":"abc","step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"\n"}}"#
    XCTAssertNil(runner.parseJSONLLine(tool: .agy, line: line))
  }

  func testUserStepIsIgnored() {
    let line =
      #"{"event":"step_update","step_update":{"conversation_id":"abc","step_index":0,"state":"DONE","step_type":"user_input"}}"#
    XCTAssertNil(runner.parseJSONLLine(tool: .agy, line: line))
  }

  func testSuccessfulResultCompletesWithTrimmedResponse() {
    let line =
      #"{"event":"result","result":{"conversation_id":"abc","status":"SUCCESS","response":"ping\n","num_turns":1}}"#
    guard case .complete(let text)? = runner.parseJSONLLine(tool: .agy, line: line) else {
      return XCTFail("expected complete")
    }
    XCTAssertEqual(text, "ping")
  }

  func testFailedResultSurfacesAnError() {
    let line =
      #"{"event":"result","result":{"conversation_id":"abc","status":"FAILED","response":"quota exceeded"}}"#
    guard case .error(let message)? = runner.parseJSONLLine(tool: .agy, line: line) else {
      return XCTFail("expected error")
    }
    XCTAssertEqual(message, "quota exceeded")
  }
}
