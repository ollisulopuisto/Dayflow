import Foundation

/// Keeps macOS App Nap away while the recorder is working.
///
/// Dayflow's whole job is recording the screen while the app sits in the
/// background — exactly the state (no visible window, not frontmost, not
/// audible) in which App Nap would otherwise throttle or suspend the
/// process and quietly punch holes in the recorded timeline. A held
/// `ProcessInfo` activity makes the app ineligible for App Nap (Energy
/// Efficiency Guide for Mac Apps).
///
/// `.background` is deliberate: it prevents App Nap and nothing else, so
/// it carries no idle-display or idle-system sleep prevention — the Mac
/// still sleeps on its normal schedule, and the recorder already pauses
/// for sleep/lock on its own (`RecorderState.paused`).
final class AppNapGuard {

  private var token: NSObjectProtocol?
  private let beginActivity: (NSActivityOptions, String) -> NSObjectProtocol?
  private let endActivity: (NSObjectProtocol) -> Void

  init(
    beginActivity: @escaping (NSActivityOptions, String) -> NSObjectProtocol? = {
      ProcessInfo.processInfo.beginActivity(options: $0, reason: $1)
    },
    endActivity: @escaping (NSObjectProtocol) -> Void = {
      ProcessInfo.processInfo.endActivity($0)
    }
  ) {
    self.beginActivity = beginActivity
    self.endActivity = endActivity
  }

  deinit {
    // Balance begin/end if the owner goes away mid-hold; a leaked activity
    // would keep the app out of App Nap until it quits.
    release()
  }

  /// Whether an assertion is currently held (tests and debugging).
  var isHolding: Bool { token != nil }

  /// Hold App Nap off until `release()`. Calling twice without a release
  /// keeps the first assertion; the reason is not replaced.
  func hold(reason: String) {
    guard token == nil else { return }
    token = beginActivity(.background, reason)
  }

  /// Release the held assertion, if any. Safe to call repeatedly.
  func release() {
    guard let token else { return }
    self.token = nil
    endActivity(token)
  }
}
