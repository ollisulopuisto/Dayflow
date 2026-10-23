import XCTest

@testable import Dayflow

final class BrowserPrivacyQueueTests: XCTestCase {
  private final class ConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private(set) var maxRunning = 0

    func enter() {
      lock.withLock {
        running += 1
        maxRunning = max(maxRunning, running)
      }
    }

    func leave() {
      lock.withLock { running -= 1 }
    }
  }

  func testAppleScriptWorkRunsOffTheMainThread() async {
    let onMain = await AppleScriptQueue.perform { Thread.isMainThread }
    XCTAssertFalse(onMain)
  }

  /// NSAppleScript is not thread safe, so every use shares one serial queue.
  func testAppleScriptWorkRunsOneAtATime() async {
    let probe = ConcurrencyProbe()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<5 {
        group.addTask {
          await AppleScriptQueue.perform {
            probe.enter()
            Thread.sleep(forTimeInterval: 0.01)
            probe.leave()
          }
        }
      }
    }
    XCTAssertEqual(probe.maxRunning, 1)
  }
}
