import AppKit

enum AppVisibility {
  /// True when a main-style window is actually on screen. Cmd-Q only hides the app, so the
  /// SwiftUI tree stays alive; periodic refreshes should skip their work then and rely on
  /// the didBecomeActive reload when the user comes back.
  @MainActor
  static var isMainWindowOnScreen: Bool {
    guard !NSApp.isHidden else { return false }
    return NSApp.windows.contains {
      $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
    }
  }
}
