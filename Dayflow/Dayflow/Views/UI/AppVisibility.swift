import AppKit

/// Whether any Dayflow window is actually on screen. Cmd-Q only hides the app, so view timers
/// keep firing unless they check this; views refresh on didBecomeActive when shown again.
@MainActor
enum AppVisibility {
  static var isOnScreen: Bool {
    guard !NSApp.isHidden else { return false }
    return NSApp.windows.contains { window in
      window.isVisible && window.occlusionState.contains(.visible)
    }
  }
}
