import XCTest
@testable import Dayflow

final class DebugLogFormatterTests: XCTestCase {

    func testMakeLog_WithEmptyArrays_ReturnsEmptySections() {
        let result = DebugLogFormatter.makeLog(timeline: [], llmCalls: [], batches: [])

        let expected = """
        --- Timeline cards: none ---

        --- LLM calls: none ---

        --- Analysis batches: none ---
        """

        XCTAssertEqual(result, expected)
    }

    func testMakeLog_WithTimelineCards_FormatsCardsCorrectly() {
        let card1 = TimelineCardDebugEntry(
            createdAt: nil,
            batchId: nil,
            day: "Mon",
            startTime: "09:00",
            endTime: "10:00",
            category: "Work",
            subcategory: "Coding",
            title: "Task A",
            summary: "Did some coding.",
            detailedSummary: "Wrote some unit tests for formatting."
        )

        let result = DebugLogFormatter.makeLog(timeline: [card1], llmCalls: [], batches: [])

        XCTAssertTrue(result.contains("--- Timeline cards (latest 1) ---"))
        XCTAssertTrue(result.contains("1. [Mon] 09:00-10:00 | Task A | Work / Coding | created unknown"))
        XCTAssertTrue(result.contains("   Summary: Did some coding."))
        XCTAssertTrue(result.contains("   Details: Wrote some unit tests for formatting."))

        // Also verify other sections are empty
        XCTAssertTrue(result.contains("--- LLM calls: none ---"))
        XCTAssertTrue(result.contains("--- Analysis batches: none ---"))
    }

    func testMakeLog_WithLLMCalls_FormatsCallsCorrectly() {
        let call1 = LLMCallDebugEntry(
            createdAt: nil,
            batchId: 42,
            callGroupId: "grp1",
            attempt: 2,
            provider: "OpenAI",
            model: "gpt-4",
            operation: "chat",
            status: "success",
            latencyMs: 1200,
            httpStatus: 200,
            requestMethod: "POST",
            requestURL: "https://api.openai.com/v1/chat/completions",
            requestBody: "{\"prompt\": \"hello\"}",
            responseBody: "{\"reply\": \"world\"}",
            errorMessage: nil
        )

        let result = DebugLogFormatter.makeLog(timeline: [], llmCalls: [call1], batches: [])

        XCTAssertTrue(result.contains("--- LLM calls (latest 1) ---"))
        XCTAssertTrue(result.contains("1. unknown | OpenAI | gpt-4 | chat | success | 1200ms | HTTP 200"))
        XCTAssertTrue(result.contains("   batch 42, group grp1, attempt 2"))
        XCTAssertTrue(result.contains("   POST https://api.openai.com/v1/chat/completions"))

        // Check payload block logic
        XCTAssertTrue(result.contains("   Request:"))
        XCTAssertTrue(result.contains("      {"))
        XCTAssertTrue(result.contains("      \"prompt\" : \"hello\""))
        XCTAssertTrue(result.contains("      }"))

        XCTAssertTrue(result.contains("   Response:"))
        XCTAssertTrue(result.contains("      \"reply\" : \"world\""))
    }

    func testMakeLog_WithLLMCallErrorsAndNoPrettyJSON_FormatsCorrectly() {
        let callError = LLMCallDebugEntry(
            createdAt: nil,
            batchId: nil,
            callGroupId: nil,
            attempt: 1,
            provider: "Local",
            model: nil,
            operation: "summary",
            status: "failed",
            latencyMs: nil,
            httpStatus: 500,
            requestMethod: nil,
            requestURL: "http://localhost:11434",
            requestBody: "invalid-json",
            responseBody: nil,
            errorMessage: "Connection refused"
        )

        let result = DebugLogFormatter.makeLog(timeline: [], llmCalls: [callError], batches: [])

        XCTAssertTrue(result.contains("1. unknown | Local | summary | failed | HTTP 500"))
        XCTAssertTrue(result.contains("   URL: http://localhost:11434"))
        XCTAssertTrue(result.contains("   Error: Connection refused"))
        XCTAssertTrue(result.contains("   Request:"))
        XCTAssertTrue(result.contains("      invalid-json"))
    }

    func testMakeLog_WithAnalysisBatches_FormatsBatchesCorrectly() {
        let batch1 = AnalysisBatchDebugEntry(
            id: 101,
            status: "completed",
            startTs: 1700000000,
            endTs: 1700003600,
            createdAt: nil,
            reason: "periodic"
        )

        let result = DebugLogFormatter.makeLog(timeline: [], llmCalls: [], batches: [batch1])

        XCTAssertTrue(result.contains("--- Analysis batches (latest 1) ---"))
        XCTAssertTrue(result.contains("1. id=101 | status=completed | created unknown"))
        XCTAssertTrue(result.contains("   reason: periodic"))

        // Just verify the window line is generated
        XCTAssertTrue(result.contains("   window: "))
    }

    func testFormatPayloadWithValidJSON() throws {
        let rawJSON = "{\"name\": \"Alice\", \"age\": 30}"
        let formatted = DebugLogFormatter.formatPayload(rawJSON)

        // We expect it to be pretty printed
        let unwrappedFormatted = try XCTUnwrap(formatted)
        // Checking format features
        XCTAssertTrue(unwrappedFormatted.contains("{\n"))
        XCTAssertTrue(unwrappedFormatted.contains("\"name\" : \"Alice\""))
        XCTAssertTrue(unwrappedFormatted.contains("\"age\" : 30"))
    }

    func testFormatPayloadWithInvalidJSON() {
        let rawText = "This is not JSON."
        let formatted = DebugLogFormatter.formatPayload(rawText)

        // It should just return the trimmed string
        XCTAssertEqual(formatted, "This is not JSON.")
    }

    func testFormatPayloadWithEmptyString() {
        XCTAssertNil(DebugLogFormatter.formatPayload(""))
        XCTAssertNil(DebugLogFormatter.formatPayload("   "))
        XCTAssertNil(DebugLogFormatter.formatPayload("\n"))
    }

    func testFormatPayloadWithNil() {
        XCTAssertNil(DebugLogFormatter.formatPayload(nil))
    }
}
