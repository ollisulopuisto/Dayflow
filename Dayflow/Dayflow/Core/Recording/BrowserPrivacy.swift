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
  @MainActor
  static func redactionLabel() -> String? {
    guard let state = frontmostBrowserState(),
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

  /// The state of the frontmost window when it belongs to a supported browser, otherwise nil.
  @MainActor
  static func frontmostBrowserState() -> State? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      let bundleID = app.bundleIdentifier
    else { return nil }

    if chromiumBundleIDs.contains(bundleID) {
      return scriptedState(bundleID: bundleID, chromium: true)
    }
    if bundleID == safariBundleID {
      return scriptedState(bundleID: bundleID, chromium: false)
    }
    if firefoxBundleIDs.contains(bundleID) {
      let title = frontWindowTitle(pid: app.processIdentifier) ?? ""
      return State(isIncognito: title.contains("Private Browsing"), url: nil)
    }
    return nil
  }

  private static func scriptedState(bundleID: String, chromium: Bool) -> State? {
    let source =
      chromium
      ? """
      tell application id "\(bundleID)"
        if (count of windows) is 0 then return ""
        return (mode of front window) & linefeed & (URL of active tab of front window)
      end tell
      """
      : """
      tell application id "\(bundleID)"
        if (count of windows) is 0 then return ""
        return "normal" & linefeed & (URL of current tab of front window)
      end tell
      """
    guard let script = NSAppleScript(source: source) else { return nil }
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
