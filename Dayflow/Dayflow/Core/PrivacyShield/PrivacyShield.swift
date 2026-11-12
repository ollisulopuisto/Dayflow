import Combine
import CoreGraphics
import Foundation

/// The masker the screen recorder runs on each captured frame. It sits outside the main actor behind a lock,
/// because the recorder reads it from its own capture tasks; `PrivacyShield` is the only writer.
final class PrivacyShieldMaskerBox: @unchecked Sendable {
  static let shared = PrivacyShieldMaskerBox()

  private let lock = NSLock()
  private var masker: PrivacyShieldFrameMasker?

  /// The masker to run on a captured frame, or nil when the shield shouldn't touch frames right now.
  func current() -> PrivacyShieldFrameMasker? {
    lock.lock()
    defer { lock.unlock() }
    return masker
  }

  func set(_ newValue: PrivacyShieldFrameMasker?) {
    lock.lock()
    masker = newValue
    lock.unlock()
  }
}

/// The Privacy Shield feature: the user's on/off switch and the masker handed to the screen recorder
/// while it's on. Upstream gates this behind a Pro or Plus plan and downloads a trained model from the
/// backend; this fork stripped both. Masking here is local and free: the masker's pattern rules
/// (passwords, API keys, private keys, setup keys, seed phrases, cards and IBANs) decide what to hide,
/// and no account, plan or network is ever involved.
@MainActor
final class PrivacyShield: ObservableObject {
  static let shared = PrivacyShield()

  enum Status: Equatable {
    case off
    case preparing
    case on
  }

  private static let enabledKey = "privacyShieldEnabled"
  private static let calloutDismissedKey = "privacyShieldCalloutDismissed"

  @Published private(set) var isEnabled: Bool
  @Published private(set) var status: Status = .off
  @Published private(set) var calloutDismissed: Bool

  private var prepareTask: Task<Void, Never>?
  /// Identifies the current prepare, so a cancelled one never overrides a newer one.
  private var prepareID = UUID()

  private init() {
    isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    calloutDismissed = UserDefaults.standard.bool(forKey: Self.calloutDismissedKey)
  }

  /// What the footer switch shows: on whenever the shield is on or getting ready, never just because it was asked for.
  var showsOn: Bool {
    isEnabled && status != .off
  }

  /// Call once at launch: re-arms the shield when it was on at quit.
  func start() {
    refresh()
  }

  /// The footer toggle: turns the local masker on or off. There is no plan to sell here.
  func toggleTapped() {
    dismissCallout()
    setEnabled(!showsOn)
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    AnalyticsService.shared.capture("privacy_shield_toggled", ["enabled": enabled])
    refresh()
  }

  func dismissCallout() {
    guard !calloutDismissed else { return }
    calloutDismissed = true
    UserDefaults.standard.set(true, forKey: Self.calloutDismissedKey)
  }

  /// Brings the masker in line with the switch.
  private func refresh() {
    guard isEnabled else {
      cancelPrepare()
      PrivacyShieldMaskerBox.shared.set(nil)
      status = .off
      return
    }
    guard PrivacyShieldMaskerBox.shared.current() == nil, prepareTask == nil else { return }
    status = .preparing
    let id = UUID()
    prepareID = id
    prepareTask = Task { [weak self] in
      // Building the rules and warming Vision up is fast but not free; keep it off the main actor.
      let masker = await Task.detached(priority: .utility) {
        let built = PrivacyShieldFrameMasker(rules: Self.makeRules())
        built.warmUp()
        return built
      }.value
      guard let self, id == self.prepareID, self.isEnabled else { return }
      PrivacyShieldMaskerBox.shared.set(masker)
      self.status = .on
      self.prepareTask = nil
    }
  }

  private func cancelPrepare() {
    prepareTask?.cancel()
    prepareTask = nil
    prepareID = UUID()
  }

  /// The rule set the masker applies. The threshold only steered the removed model's scores; the
  /// pattern rules don't use it, but the type still asks for one (0.5 is what upstream scored with).
  private nonisolated static func makeRules() -> PIIMaskRules {
    PIIMaskRules(threshold: 0.5, bip39Words: BIP39Wordlist.words)
  }
}
