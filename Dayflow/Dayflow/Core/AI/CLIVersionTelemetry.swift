import Foundation

/// Reports which Codex and Claude CLI versions are installed, as PostHog super
/// properties (so every event carries them) and person properties (so the
/// version distribution across users is chartable).
@MainActor
enum CLIVersionTelemetry {
  private static let staleAfter: TimeInterval = 24 * 60 * 60
  private static var lastRefresh: Date?

  private enum DefaultsKey {
    static let lastRefresh = "cliVersionTelemetry.lastRefresh"
    static let lastProperties = "cliVersionTelemetry.lastProperties"
  }

  /// Dayflow runs for weeks at a time and the CLIs update underneath it, so
  /// the heartbeat calls this to re-probe about once a day. The timestamp and
  /// last-known versions persist across launches, so a relaunch inside the TTL
  /// registers the cached versions instead of spawning fresh login-shell probes.
  static func refreshIfStale(now: Date = Date(), defaults: UserDefaults = .standard) {
    registerLastKnownProperties(defaults: defaults)
    let persisted = defaults.object(forKey: DefaultsKey.lastRefresh) as? Date
    guard isStale(lastRefresh: lastRefresh ?? persisted, now: now) else { return }
    refresh(now: now, defaults: defaults)
  }

  static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) {
    guard AnalyticsService.shared.isOptedIn else { return }
    lastRefresh = now
    defaults.set(now, forKey: DefaultsKey.lastRefresh)

    // Probing spawns login shells, which can take seconds with a heavy shell config.
    Task.detached(priority: .utility) {
      let properties = probe()
      await MainActor.run {
        defaults.set(properties, forKey: DefaultsKey.lastProperties)
        AnalyticsService.shared.registerSuperProperties(properties)
        AnalyticsService.shared.setPersonProperties(properties)
      }
    }
  }

  /// Re-registers the versions from the previous probe so analytics keep
  /// carrying them before this launch's probe lands. No-op before the first
  /// successful probe or when analytics are opted out.
  private static func registerLastKnownProperties(defaults: UserDefaults) {
    guard AnalyticsService.shared.isOptedIn,
      let properties = defaults.dictionary(forKey: DefaultsKey.lastProperties) as? [String: String],
      !properties.isEmpty
    else { return }
    AnalyticsService.shared.registerSuperProperties(properties)
    AnalyticsService.shared.setPersonProperties(properties)
  }

  /// The pure staleness decision, separated for tests. nil means never probed.
  nonisolated static func isStale(lastRefresh: Date?, now: Date) -> Bool {
    guard let lastRefresh else { return true }
    // A persisted wall-clock timestamp can be in the future after a clock
    // correction. Re-probe once rather than suppressing telemetry until that
    // future date plus the TTL. A successful refresh replaces the timestamp.
    let age = now.timeIntervalSince(lastRefresh)
    return age < 0 || age >= staleAfter
  }

  private nonisolated static func probe() -> [String: String] {
    // Drop the cached resolution so an updated binary reports its new version.
    CodexExecutableResolver.shared.invalidate()
    let codex = CodexExecutableResolver.shared.resolve()
    let claude = LoginShellRunner.version(of: "claude")

    return [
      "codex_cli_version": codex?.version ?? "not_installed",
      "codex_cli_source": codex?.source.rawValue ?? "not_installed",
      "claude_cli_version": claude.map(numericVersion) ?? "not_installed",
    ]
  }

  /// "2.1.4 (Claude Code)" -> "2.1.4". Keeps stray shell output out of analytics.
  nonisolated static func numericVersion(_ versionSummary: String) -> String {
    guard
      let range = versionSummary.range(of: #"\d+(?:\.\d+){1,3}"#, options: .regularExpression)
    else { return "unknown" }
    return String(versionSummary[range])
  }
}
