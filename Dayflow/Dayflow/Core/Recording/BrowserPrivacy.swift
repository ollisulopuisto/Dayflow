import AppKit
import CoreGraphics
import Foundation

/// Hides screenshots taken while a browser shows a private window or an excluded site.
///
/// Chromium browsers and Safari are read through AppleScript (window mode and the active tab's
/// URL). Firefox has no URL scripting, so only its private-window state is detected, from the
/// window title. Everything is decided before the screen is captured, so a redacted frame never
/// reaches disk.
enum BrowserPrivacy {
  enum Redaction: Equatable {
    case privateWindow
    case excludedSite
  }

  struct State: Equatable {
    let isIncognito: Bool
    let url: String?
  }

  static let hideIncognitoKey = "privacyHideIncognitoWindows"
  static let excludedDomainsKey = "privacyExcludedDomains"

  /// Private and incognito windows are hidden unless the user turns this off.
  static var hidesIncognito: Bool {
    UserDefaults.standard.object(forKey: hideIncognitoKey) as? Bool ?? true
  }

  static var excludedDomains: [String] {
    parseDomains(UserDefaults.standard.string(forKey: excludedDomainsKey) ?? "")
  }

  /// Accepts commas, spaces or new lines between domains. Scheme, "www." and "*." are dropped.
  static func parseDomains(_ text: String) -> [String] {
    text
      .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
      .map { raw -> String in
        var domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = domain.range(of: "://") { domain = String(domain[range.upperBound...]) }
        if domain.hasPrefix("*.") { domain.removeFirst(2) }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        if let slash = domain.firstIndex(of: "/") { domain = String(domain[..<slash]) }
        return domain
      }
      .filter { !$0.isEmpty }
  }

  static func host(from urlString: String) -> String? {
    URLComponents(string: urlString)?.host?.lowercased()
  }

  /// A domain matches itself and every subdomain of it, but not look-alikes such as "notexample.com".
  static func isExcluded(host: String, excludedDomains: [String]) -> Bool {
    excludedDomains.contains { domain in
      host == domain || host.hasSuffix("." + domain)
    }
  }

  static func redactionReason(
    isIncognito: Bool,
    url: String?,
    hidesIncognito: Bool,
    excludedDomains: [String]
  ) -> Redaction? {
    if isIncognito && hidesIncognito {
      return .privateWindow
    }
    if let url, let host = host(from: url),
      isExcluded(host: host, excludedDomains: excludedDomains)
    {
      return .excludedSite
    }
    return nil
  }

  static func label(for redaction: Redaction) -> String {
    switch redaction {
    case .privateWindow: return String(localized: "Private browsing")
    case .excludedSite: return String(localized: "Excluded site")
    }
  }

  /// The label to draw instead of the screen, or nil when the frontmost window may be captured.
  /// The browser is asked on `AppleScriptQueue`, so a slow or hung browser never blocks the main thread.
  static func redactionLabel() async -> String? {
    guard let state = await frontmostBrowserState(),
      let redaction = redactionReason(
        isIncognito: state.isIncognito,
        url: state.url,
        hidesIncognito: hidesIncognito,
        excludedDomains: excludedDomains
      )
    else { return nil }
    return label(for: redaction)
  }

  private static let chromiumBundleIDs: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "org.chromium.Chromium",
    "com.brave.Browser",
    "com.microsoft.edgemac",
    "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
    "company.thebrowser.Browser",
  ]
  private static let safariBundleID = "com.apple.Safari"
  private static let firefoxBundleIDs: Set<String> = ["org.mozilla.firefox"]

  enum BrowserKind {
    case chromium
    case safari
    case firefox
  }

  /// Whether asking this browser anything could change the decision. Each check is an Apple
  /// Event or a window list scan on every capture, so it is skipped when no setting needs it.
  static func needsCheck(_ kind: BrowserKind, hidesIncognito: Bool, excludedDomains: [String])
    -> Bool
  {
    switch kind {
    case .chromium: return hidesIncognito || !excludedDomains.isEmpty
    case .safari: return !excludedDomains.isEmpty  // Safari only reports the URL.
    case .firefox: return hidesIncognito  // Firefox only reports its window title.
    }
  }

  /// The frontmost app when it is a supported browser that a current setting needs to ask.
  struct Target: Sendable {
    let kind: BrowserKind
    let bundleID: String
    let pid: pid_t
  }

  @MainActor
  static func frontmostTarget() -> Target? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      let bundleID = app.bundleIdentifier
    else { return nil }

    let kind: BrowserKind
    if chromiumBundleIDs.contains(bundleID) {
      kind = .chromium
    } else if bundleID == safariBundleID {
      kind = .safari
    } else if firefoxBundleIDs.contains(bundleID) {
      kind = .firefox
    } else {
      return nil
    }
    guard needsCheck(kind, hidesIncognito: hidesIncognito, excludedDomains: excludedDomains)
    else { return nil }
    return Target(kind: kind, bundleID: bundleID, pid: app.processIdentifier)
  }

  /// The state of the frontmost window when it belongs to a supported browser, otherwise nil.
  static func frontmostBrowserState() async -> State? {
    guard let target = await MainActor.run(body: { frontmostTarget() }) else { return nil }
    return await AppleScriptQueue.perform { state(of: target) }
  }

  private static func state(of target: Target) -> State? {
    switch target.kind {
    case .chromium:
      return scriptedState(bundleID: target.bundleID, chromium: true)
    case .safari:
      return scriptedState(bundleID: target.bundleID, chromium: false)
    case .firefox:
      let title = frontWindowTitle(pid: target.pid) ?? ""
      return State(isIncognito: title.contains("Private Browsing"), url: nil)
    }
  }

  /// Compiled once per browser; compiling AppleScript on every capture was wasted work.
  /// Only touched from `AppleScriptQueue`.
  nonisolated(unsafe) private static var compiledScripts: [String: NSAppleScript] = [:]

  private static func compiledScript(bundleID: String, chromium: Bool) -> NSAppleScript? {
    if let cached = compiledScripts[bundleID] { return cached }
    // The timeout bounds how long the queue is held by a hung browser (the default is 2 minutes).
    let body =
      chromium
      ? "return (mode of front window) & linefeed & (URL of active tab of front window)"
      : "return \"normal\" & linefeed & (URL of current tab of front window)"
    let source = """
      with timeout of 2 seconds
        tell application id "\(bundleID)"
          if (count of windows) is 0 then return ""
          \(body)
        end tell
      end timeout
      """
    guard let script = NSAppleScript(source: source) else { return nil }
    var error: NSDictionary?
    guard script.compileAndReturnError(&error) else { return nil }
    compiledScripts[bundleID] = script
    return script
  }

  private static func scriptedState(bundleID: String, chromium: Bool) -> State? {
    guard let script = compiledScript(bundleID: bundleID, chromium: chromium) else { return nil }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    guard error == nil, let text = result.stringValue, !text.isEmpty else { return nil }

    let lines = text.components(separatedBy: "\n")
    let mode = lines.first ?? ""
    let url = lines.count > 1 ? lines[1] : nil
    return State(isIncognito: mode == "incognito", url: url)
  }

  private static func frontWindowTitle(pid: pid_t) -> String? {
    let windows =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    let match = windows.first { window in
      (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
        && (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
    }
    return match?[kCGWindowName as String] as? String
  }
}

/// NSAppleScript is not thread safe, so all use shares one serial queue, away from the main thread.
enum AppleScriptQueue {
  private static let queue = DispatchQueue(
    label: "so.dayflow.browser-privacy.applescript", qos: .utility)

  static func perform<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: work()) }
    }
  }
}
