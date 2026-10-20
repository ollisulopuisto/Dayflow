import XCTest
@testable import Dayflow

final class FlowNativeSnapshotTests: XCTestCase {

    func testBridgePayloadGeneration_minimal() throws {
        let snapshot = FlowNativeSnapshot()
        let payload = snapshot.bridgePayload

        XCTAssertEqual(payload["phase"] as? String, FlowPhase.idle.rawValue)
        XCTAssertEqual(payload["alertStyle"] as? String, FlowAlertStyle.friendly.rawValue)
        XCTAssertEqual(payload["alwaysOn"] as? Bool, false)

        XCTAssertNil(payload["sessionEndsAt"])
        XCTAssertNil(payload["breakEndsAt"])
        XCTAssertNil(payload["sessionStartedAt"])
        XCTAssertNil(payload["goals"])
        XCTAssertNil(payload["goalTasks"])
    }

    func testBridgePayloadGeneration_full() throws {
        var snapshot = FlowNativeSnapshot()
        snapshot.phase = .active
        snapshot.alertStyle = .feisty
        snapshot.alwaysOn = true
        snapshot.sessionEndsAt = 1000
        snapshot.breakEndsAt = 2000
        snapshot.sessionStartedAt = 500
        snapshot.goals = ["goal1", "goal2"]
        snapshot.goalTasks = [
            FlowGoalTask(id: "1", title: "Task 1"),
            FlowGoalTask(id: "2", title: "Task 2")
        ]

        let payload = snapshot.bridgePayload

        XCTAssertEqual(payload["phase"] as? String, FlowPhase.active.rawValue)
        XCTAssertEqual(payload["alertStyle"] as? String, FlowAlertStyle.feisty.rawValue)
        XCTAssertEqual(payload["alwaysOn"] as? Bool, true)
        XCTAssertEqual(payload["sessionEndsAt"] as? Int, 1000)
        XCTAssertEqual(payload["breakEndsAt"] as? Int, 2000)
        XCTAssertEqual(payload["sessionStartedAt"] as? Int, 500)
        XCTAssertEqual(payload["goals"] as? [String], ["goal1", "goal2"])

        let goalTasksPayload = try XCTUnwrap(payload["goalTasks"] as? [[String: Any]])
        XCTAssertEqual(goalTasksPayload.count, 2)
        XCTAssertEqual(goalTasksPayload[0]["id"] as? String, "1")
        XCTAssertEqual(goalTasksPayload[0]["title"] as? String, "Task 1")
        XCTAssertEqual(goalTasksPayload[1]["id"] as? String, "2")
        XCTAssertEqual(goalTasksPayload[1]["title"] as? String, "Task 2")
    }

    func testBridgePayloadRoundtrip() throws {
        var original = FlowNativeSnapshot()
        original.phase = .onBreak
        original.alertStyle = .quiet
        original.alwaysOn = false
        original.sessionEndsAt = 3000
        original.breakEndsAt = 4000
        original.sessionStartedAt = 2500
        original.goals = ["Finish tests"]
        original.goalTasks = [
            FlowGoalTask(id: "task_a", title: "Task A")
        ]

        let payload = original.bridgePayload

        let recreated = try XCTUnwrap(FlowNativeSnapshot(bridgePayload: payload))

        XCTAssertEqual(original, recreated)
    }
}
