import AppKit
import SwiftUI

// Menu commands share one registry. Local text/editor commands stay local.
enum AppShortcutRegistry {
  struct Binding {
    let key: KeyEquivalent
    let modifiers: EventModifiers
  }

  static let quit = Binding(key: "q", modifiers: .command)
  static let hide = Binding(key: "h", modifiers: .command)
  static let hideOthers = Binding(key: "h", modifiers: [.command, .option])
  static let resetOnboarding = Binding(key: "R", modifiers: [.command, .shift])
  static let settings = Binding(key: ",", modifiers: .command)
  static let zoomIn = Binding(key: "+", modifiers: .command)
  static let zoomOut = Binding(key: "-", modifiers: .command)
  static let previousPeriod = Binding(key: .leftArrow, modifiers: .command)
  static let nextPeriod = Binding(key: .rightArrow, modifiers: .command)
  static let today = Binding(key: "t", modifiers: .command)
  static let search = Binding(key: "f", modifiers: .command)
  static let releaseNotes = Binding(key: "N", modifiers: [.command, .shift])
  static func section(_ number: Int) -> Binding {
    Binding(key: KeyEquivalent(Character(String(number))), modifiers: .command)
  }

  @MainActor static func hideApplication(hide: () -> Void = { NSApp.hide(nil) }) {
    hide()
  }
}
