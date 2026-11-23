import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = NSMenu()
  private var cancellable: AnyCancellable?
  private var problemCancellable: AnyCancellable?
  /// Orange dot on the icon while a provider problem is waiting on the user.
  private let problemDot = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
  /// The live controller, so floating cards (like the Daily brief notice) can
  /// sit under the menu bar icon.
  private(set) static weak var current: StatusBarController?
  private var visibilityCancellable: AnyCancellable?

  override init() {
    super.init()
    Self.current = self
    menu.delegate = self
    statusItem.menu = menu

    if let button = statusItem.button {
      button.imageScaling = .scaleProportionallyDown
      button.imagePosition = .imageOnly

      let isRecording = AppState.shared.isRecording
      button.image = menuBarIcon(isRecording: isRecording)

      problemDot.wantsLayer = true
      problemDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
      problemDot.layer?.cornerRadius = 3
      problemDot.isHidden = true
      button.addSubview(problemDot)
    }

    problemCancellable = ProviderProblemCenter.shared.$problem
      .map { $0 != nil }
      .removeDuplicates()
      .sink { [weak self] hasProblem in
        self?.updateProblemDot(hasProblem: hasProblem)
      }

    // Observe recording state changes and update icon
    cancellable = AppState.shared.$isRecording
      .removeDuplicates()
      .sink { [weak self] isRecording in
        self?.updateIcon(isRecording: isRecording)
      }

    visibilityCancellable = UserDefaults.standard.publisher(for: \.showMenuBarIcon)
      .sink { [weak self] isVisible in
        self?.statusItem.isVisible = isVisible
      }
  }

  /// Where the menu bar icon is on screen, or nil when macOS is hiding it.
  func iconFrameOnScreen() -> NSRect? {
    guard let button = statusItem.button, let window = button.window, window.isVisible else {
      return nil
    }
    return window.convertToScreen(button.convert(button.bounds, to: nil))
  }

  /// Puts the dot in the icon's top right corner. Hidden during a Flow session, when the icon
  /// is replaced by the wide Flow pill.
  private func updateProblemDot(hasProblem: Bool) {
    guard let button = statusItem.button else { return }
    let size = problemDot.frame.size
    let y = button.isFlipped ? 3 : button.bounds.height - size.height - 3
    problemDot.frame.origin = CGPoint(x: button.bounds.width - size.width - 2, y: y)
    problemDot.isHidden = !hasProblem
  }

  private func updateIcon(isRecording: Bool) {
    statusItem.button?.image = menuBarIcon(isRecording: isRecording)
  }

  private func menuBarIcon(isRecording: Bool) -> NSImage? {
    let name = isRecording ? "MenuBarOnIcon" : "MenuBarOffIcon"
    guard let image = NSImage(named: name)?.copy() as? NSImage else { return nil }
    image.size = NSSize(width: 22, height: 18)
    return image
  }

  // MARK: - Menu

  // Rebuilt every time the menu opens, so it always reflects the current recording state.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    if let problem = ProviderProblemCenter.shared.problem {
      menu.addItem(problemItem(problem))
      if let backup = problem.backupOfferProviderID {
        menu.addItem(
          actionItem(
            String(localized: "Use \(ProviderSignIn.displayName(for: backup)) as backup instead"),
            #selector(useBackupProvider), symbol: "arrow.triangle.branch"))
      }
      menu.addItem(.separator())
    }

    switch RecordingControl.currentMode() {
    case .active:
      menu.addItem(.sectionHeader(title: String(localized: "Pause Dayflow")))
      menu.addItem(pauseStripItem())
    case .pausedTimed(let endTime):
      let time = endTime.formatted(date: .omitted, time: .shortened)
      menu.addItem(infoItem(String(localized: "Paused until \(time)")))
      menu.addItem(resumeItem())
    case .pausedIndefinite, .stopped:
      menu.addItem(resumeItem())
    }

    menu.addItem(.separator())
    menu.addItem(
      actionItem(String(localized: "Open Dayflow"), #selector(openDayflow), symbol: "macwindow"))
    menu.addItem(actionItem(String(localized: "Open Recordings"), #selector(openRecordingsFolder)))
    menu.addItem(actionItem(String(localized: "Check for Updates"), #selector(checkForUpdates)))
    menu.addItem(.separator())
    menu.addItem(
      actionItem(
        String(localized: "Quit Completely"), #selector(quitDayflow), keyEquivalent: "q",
        symbol: "power", tint: .systemRed))
  }

  func menuDidClose(_ menu: NSMenu) {
    menu.removeAllItems()
  }

  /// "Claude is signed out · 3 hrs waiting · Click to sign in"
  private func problemItem(_ problem: TimelineFailureToastPayload) -> NSMenuItem {
    var parts = [problem.title ?? String(localized: "Dayflow needs a hand")]
    if let waiting = problem.waitingText {
      parts.append(String(localized: "\(waiting) waiting"))
    }
    parts.append(
      problem.signInProviderID == nil
        ? String(localized: "Click to fix") : String(localized: "Click to sign in"))
    return actionItem(
      parts.joined(separator: " · "), #selector(fixProviderProblem),
      symbol: "exclamationmark.triangle.fill", tint: .systemOrange)
  }

  private func resumeItem() -> NSMenuItem {
    actionItem(
      String(localized: "Resume Dayflow"), #selector(resumeRecording), symbol: "play.circle",
      tint: .systemBlue)
  }

  /// A plain menu item. Items without a symbol get a blank one, so every title
  /// lines up after the icon column the way the design lays them out.
  private func actionItem(
    _ title: String, _ action: Selector, keyEquivalent: String = "", symbol: String? = nil,
    tint: NSColor? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    if let symbol {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      item.image =
        tint.flatMap { image?.withSymbolConfiguration(.init(paletteColors: [$0])) } ?? image
    } else {
      item.image = NSImage(size: NSSize(width: 15, height: 13))
    }
    // macOS 27 hides menu item images unless an item asks for them.
    #if compiler(>=6.4)
      if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    #endif
    return item
  }

  /// The horizontal row of pause lengths. Custom views don't close the menu on
  /// click the way normal items do, so the handler closes it first.
  private func pauseStripItem() -> NSMenuItem {
    let strip = StatusMenuPauseStrip(durations: PausePresets.durations) { [weak self] duration in
      self?.menu.cancelTracking()
      PauseManager.shared.pause(for: duration, source: .menuBar)
    }
    let host = NSHostingView(rootView: strip)
    host.frame = NSRect(x: 0, y: 0, width: 220, height: StatusMenuPauseStrip.height)
    host.autoresizingMask = [.width]

    let item = NSMenuItem()
    item.view = host
    return item
  }

  // No action, so the menu shows it greyed out as a status line.
  private func infoItem(_ title: String) -> NSMenuItem {
    NSMenuItem(title: title, action: nil, keyEquivalent: "")
  }

  // MARK: - Actions

  @objc private func resumeRecording() {
    if PauseManager.shared.isPaused {
      PauseManager.shared.resume(source: .userClickedMenuBar)
    } else {
      RecordingControl.start(reason: "user_menu_bar")
    }
  }

  /// Opens Dayflow on the fix-it card, starting the browser sign-in when that is the fix.
  @objc private func fixProviderProblem() {
    guard let problem = ProviderProblemCenter.shared.problem else { return }
    AnalyticsService.shared.capture("provider_problem_menu_item_clicked", problem.analyticsProps)
    openDayflow()
    NotificationCenter.default.post(name: .navigateToTimeline, object: nil)
    if let provider = problem.signInProviderID {
      ProviderSignIn.shared.start(provider, source: "menu_bar")
    }
    // If the main window is still opening, it picks the request up when it appears.
    ProviderProblemCenter.shared.showCardAgain()
  }

  /// Makes the other tool on this Mac the backup provider, so the waiting recordings get
  /// processed without the user fixing the first provider.
  @objc private func useBackupProvider() {
    guard let problem = ProviderProblemCenter.shared.problem,
      let backup = problem.backupOfferProviderID
    else { return }
    let saved = ProviderProblemCenter.shared.acceptBackupOffer(backup, source: "menu_bar_offer")
    var props = problem.analyticsProps
    props["saved"] = saved
    AnalyticsService.shared.capture("provider_problem_menu_backup_clicked", props)
    // Saving failed, so show the card, which can take the user to Settings.
    if !saved {
      openDayflow()
      NotificationCenter.default.post(name: .navigateToTimeline, object: nil)
      ProviderProblemCenter.shared.showCardAgain()
    }
  }

  @objc private func openDayflow() {
    let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    if showDockIcon {
      NSApp.setActivationPolicy(.regular)
    }

    NSApp.unhide(nil)
    MainWindowController.shared.showMainWindow()
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openRecordingsFolder() {
    NSWorkspace.shared.open(StorageManager.shared.recordingsRoot)
  }

  @objc private func checkForUpdates() {
    UpdaterManager.shared.checkForUpdates(showUI: true)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quitDayflow() {
    AppDelegate.permitTermination(reason: "menu_bar_quit")
    NSApp.terminate(nil)
  }
}

extension UserDefaults {
  // KVO needs the property name to match the defaults key.
  @objc dynamic var showMenuBarIcon: Bool {
    object(forKey: "showMenuBarIcon") as? Bool ?? true
  }
}
