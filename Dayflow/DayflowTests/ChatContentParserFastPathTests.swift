import XCTest

@testable import Dayflow

final class ChatContentParserFastPathTests: XCTestCase {
  func testPlainTextIsOneTextBlock() {
    let blocks = ChatContentParser.blocks(from: "You focused most on Tuesday.")
    XCTAssertEqual(blocks.count, 1)
    guard case .text(_, let content)? = blocks.first else { return XCTFail("expected text") }
    XCTAssertEqual(content, "You focused most on Tuesday.")
  }

  func testChartFenceIsStillParsed() {
    let text = "Here:\n```chart type=bar\n{}\n```\nDone."
    let blocks = ChatContentParser.blocks(from: text)
    XCTAssertGreaterThan(blocks.count, 1)
  }
}
