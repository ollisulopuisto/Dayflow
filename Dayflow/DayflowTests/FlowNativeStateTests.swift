import XCTest
@testable import Dayflow

final class FlowNativeStateTests: XCTestCase {

    func testInitWithValidMinimalPayload() throws {
        let payload: [String: Any] = [
            "phase": "active"
        ]
        let snapshot = try XCTUnwrap(FlowNativeSnapshot(bridgePayload: payload))
        XCTAssertEqual(snapshot.phase, .active)
        XCTAssertEqual(snapshot.alertStyle, .friendly) // Default
        XCTAssertNil(snapshot.sessionEndsAt)
        XCTAssertNil(snapshot.breakEndsAt)
        XCTAssertFalse(snapshot.alwaysOn) // Default
        XCTAssertNil(snapshot.sessionStartedAt)
        XCTAssertNil(snapshot.goals)
        XCTAssertNil(snapshot.goalTasks)
    }

    func testInitWithValidFullPayload() throws {
        let payload: [String: Any] = [
            "phase": "break",
            "alertStyle": "feisty",
            "sessionEndsAt": 1000,
            "breakEndsAt": 2000,
            "alwaysOn": true,
            "sessionStartedAt": 500,
            "goals": ["Goal 1", "Goal 2"],
            "goalTasks": [
                ["id": "t1", "title": "Task 1"],
                ["id": "t2", "title": "Task 2"]
            ]
        ]

        let snapshot = try XCTUnwrap(FlowNativeSnapshot(bridgePayload: payload))
        XCTAssertEqual(snapshot.phase, .onBreak)
        XCTAssertEqual(snapshot.alertStyle, .feisty)
        XCTAssertEqual(snapshot.sessionEndsAt, 1000)
        XCTAssertEqual(snapshot.breakEndsAt, 2000)
        XCTAssertTrue(snapshot.alwaysOn)
        XCTAssertEqual(snapshot.sessionStartedAt, 500)
        XCTAssertEqual(snapshot.goals, ["Goal 1", "Goal 2"])
        XCTAssertEqual(snapshot.goalTasks, [
            FlowGoalTask(id: "t1", title: "Task 1"),
            FlowGoalTask(id: "t2", title: "Task 2")
        ])
    }

    func testInitWithInvalidPhase() {
        let payload: [String: Any] = [
            "phase": "invalid_phase"
        ]
        XCTAssertNil(FlowNativeSnapshot(bridgePayload: payload))
    }

    func testInitWithMissingPhase() {
        let payload: [String: Any] = [
            "alertStyle": "quiet"
        ]
        XCTAssertNil(FlowNativeSnapshot(bridgePayload: payload))
    }

    func testInitWithInvalidAlertStyle() throws {
        let payload: [String: Any] = [
            "phase": "idle",
            "alertStyle": "invalid_style"
        ]
        let snapshot = try XCTUnwrap(FlowNativeSnapshot(bridgePayload: payload))
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertEqual(snapshot.alertStyle, .friendly) // Fallback to friendly
    }

    func testInitWithInvalidGoalTasks() throws {
        let payload: [String: Any] = [
            "phase": "active",
            "goalTasks": [
                ["id": "t1", "title": "Task 1"], // Valid
                ["id": "t2"], // Missing title
                ["title": "Task 3"], // Missing id
                ["id": "t4", "title": 42], // Invalid title type
                "invalid_string", // Not a dictionary
                ["id": "t5", "title": "Task 5"] // Valid
            ]
        ]
        let snapshot = try XCTUnwrap(FlowNativeSnapshot(bridgePayload: payload))
        XCTAssertEqual(snapshot.phase, .active)

        let expectedTasks = [
            FlowGoalTask(id: "t1", title: "Task 1"),
            FlowGoalTask(id: "t5", title: "Task 5")
        ]
        XCTAssertEqual(snapshot.goalTasks, expectedTasks)
    }
}
