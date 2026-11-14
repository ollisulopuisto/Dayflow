import XCTest

@testable import Dayflow

final class ChatCLIProcessRunnerTests: XCTestCase {
  private let runner = ChatCLIProcessRunner()

  func testInvalidTransportLongFormExtractsExplicitConfigPath() throws {
    let tempDirectory = try makeTempDirectory()
    let configURL =
      tempDirectory
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("config.toml")
      .standardizedFileURL
    let stderr = """
      Error: failed to load configuration

      Caused by:
          0: \(configURL.path):1:1: invalid transport
          1: invalid transport
             in `mcp_servers.computer-use`
      """

    XCTAssertEqual(
      runner.invalidTransportConfigURL(from: stderr)?.path,
      configURL.path
    )
  }

  func testInvalidTransportShortFormsUseFallbackConfigPath() throws {
    let fallbackConfigURL = try makeFallbackConfigURL()
    let cases = [
      """
      Error loading config.toml: invalid transport
      in `mcp_servers.computer-use`
      """,
      """
      Error loading config.toml: invalid transport
      in `mcp_servers.cloudflare-api`
      """,
      """
      (anon):setopt:7: can't change option: monitor

      [ERROR]: gitstatus failed to initialize.

      Error loading config.toml: invalid transport
      in `mcp_servers.computer-use`
      """,
      """
      (anon):setopt:7: can't change option: monitor
      (eval):1: can't change option: zle

      Error loading config.toml: invalid transport
      in `mcp_servers.computer-use`
      """,
    ]

    for stderr in cases {
      let configURL = runner.invalidTransportConfigURL(
        from: stderr,
        fallbackConfigURL: fallbackConfigURL
      )
      XCTAssertEqual(
        configURL?.path,
        fallbackConfigURL.path
      )
    }
  }

  func testInvalidTransportDetectionIsCaseInsensitive() {
    XCTAssertTrue(
      runner.containsInvalidTransportError("Error loading config.toml: Invalid Transport")
    )
  }

  func testFallbackRetryDoesNotCarryUserMCPDisableOverrides() {
    XCTAssertTrue(runner.shouldDisableConfiguredCodexMCPServers(processEnvironment: [:]))
    XCTAssertFalse(
      runner.shouldDisableConfiguredCodexMCPServers(
        processEnvironment: ["CODEX_HOME": "/tmp/dayflow-codex-home"]
      )
    )
  }

  func testFallbackContextCopiesAuthIntoTemporaryCodexHome() throws {
    let tempDirectory = try makeTempDirectory()
    let sourceCodexHome = tempDirectory.appendingPathComponent(
      "source-codex-home",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: sourceCodexHome,
      withIntermediateDirectories: true
    )

    let configURL = sourceCodexHome.appendingPathComponent("config.toml")
    let authURL = sourceCodexHome.appendingPathComponent("auth.json")
    try #"{"token":"secret"}"#.write(to: authURL, atomically: true, encoding: .utf8)

    let fallback = try XCTUnwrap(
      runner.makeCodexFallbackContext(
        fromInvalidTransportStderr: """
          Error loading config.toml: invalid transport
          in `mcp_servers.computer-use`
          """,
        workingDirectory: tempDirectory,
        fallbackConfigURL: configURL
      )
    )
    defer { fallback.cleanup() }

    let codexHome = try XCTUnwrap(fallback.environment["CODEX_HOME"])
    let copiedAuthURL = URL(fileURLWithPath: codexHome)
      .appendingPathComponent("auth.json")
    XCTAssertEqual(fallback.brokenConfigURL.path, configURL.standardizedFileURL.path)
    XCTAssertTrue(fallback.didCopyAuth)
    XCTAssertEqual(
      try String(contentsOf: copiedAuthURL, encoding: .utf8),
      #"{"token":"secret"}"#
    )
  }

  func testFallbackContextBypassesProjectScopedCodexConfig() throws {
    let tempDirectory = try makeTempDirectory()
    let repoURL = tempDirectory.appendingPathComponent("repo", isDirectory: true)
    let workingDirectory = repoURL.appendingPathComponent("subdir", isDirectory: true)
    let projectCodexHome = repoURL.appendingPathComponent(".codex", isDirectory: true)
    let projectConfigURL = projectCodexHome.appendingPathComponent("config.toml")

    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projectCodexHome, withIntermediateDirectories: true)

    let stderr = """
      Error: failed to load configuration

      Caused by:
          0: \(projectConfigURL.path):1:1: invalid transport
          1: invalid transport
             in `mcp_servers.computer-use`
      """

    XCTAssertNotNil(
      runner.makeCodexFallbackContext(
        fromInvalidTransportStderr: stderr,
        workingDirectory: workingDirectory
      )
    )
  }

  func testLoginShellRunnerShellEscape() {
    let injectionPayload = "model'; touch /tmp/pwned; echo '"
    let escaped = LoginShellRunner.shellEscape(injectionPayload)
    XCTAssertEqual(escaped, "'model'\\''; touch /tmp/pwned; echo '\\'''")
    XCTAssertTrue(escaped.hasPrefix("'"))
    XCTAssertTrue(escaped.hasSuffix("'"))

    let specialChars = "hello $WORLD `whoami` \"double\" 'single' ; & |"
    let escapedSpecial = LoginShellRunner.shellEscape(specialChars)
    XCTAssertEqual(escapedSpecial, "'hello $WORLD `whoami` \"double\" '\\''single'\\'' ; & |'")
  }

  func testClaudeCommandPartsShellEscape() {
    let injectionModel = "gpt-4o'; echo 'vulnerable"
    let injectionSession = "session123'; rm -rf /; echo '"
    let injectionEffort = "high'; touch /tmp/test; echo '"
    let injectionPrompt = "Hello world'; whoami; echo '"

    let cmdParts = runner.buildClaudeCommandParts(
      prompt: injectionPrompt,
      imagePaths: [],
      model: injectionModel,
      reasoningEffort: injectionEffort,
      disableTools: false,
      sessionMode: .resume(id: injectionSession)
    )

    XCTAssertTrue(cmdParts.contains(LoginShellRunner.shellEscape(injectionModel)))
    XCTAssertTrue(cmdParts.contains(LoginShellRunner.shellEscape(injectionSession)))
    XCTAssertTrue(cmdParts.contains(LoginShellRunner.shellEscape(injectionEffort)))
    XCTAssertTrue(cmdParts.contains(LoginShellRunner.shellEscape(injectionPrompt)))

    let streamingCmdParts = runner.buildClaudeStreamingCommandParts(
      prompt: injectionPrompt,
      model: injectionModel,
      reasoningEffort: injectionEffort,
      sessionId: injectionSession
    )

    XCTAssertTrue(streamingCmdParts.contains(LoginShellRunner.shellEscape(injectionModel)))
    XCTAssertTrue(streamingCmdParts.contains(LoginShellRunner.shellEscape(injectionSession)))
    XCTAssertTrue(streamingCmdParts.contains(LoginShellRunner.shellEscape(injectionEffort)))
    XCTAssertTrue(streamingCmdParts.contains(LoginShellRunner.shellEscape(injectionPrompt)))
  }

  private func makeFallbackConfigURL() throws -> URL {
    try makeTempDirectory()
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("config.toml")
      .standardizedFileURL
  }

  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ChatCLIProcessRunnerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }
}

/// Daily brief link pictures are off in this fork, and never reach local services.
final class DailyBriefLinkImagesTests: XCTestCase {
  func testLinkPicturesAreOffAndSaveFetchesNothing() {
    XCTAssertFalse(DailyBriefLinkImages.isEnabled)
    let links = [DailyBriefLinkImages.Link(pageURL: "http://127.0.0.1:1/x", hintImageURL: nil)]
    let saved = DailyBriefLinkImages.save(links, into: FileManager.default.temporaryDirectory)
    XCTAssertTrue(saved.isEmpty)
  }

  func testLoopbackPrivateAndLocalHostsAreRefused() {
    let refused = [
      "http://localhost/a.png", "http://foo.local/a.png", "http://127.0.0.1:8080/a.png",
      "http://10.0.0.5/a.png", "http://172.16.0.1/a.png", "http://172.31.255.1/a.png",
      "http://192.168.1.1/a.png", "http://169.254.169.254/a.png", "http://[::1]/a.png",
      "http://[fd00::1]/a.png", "http://[fe80::1]/a.png", "file:///etc/passwd", "ftp://example.com/a",
    ]
    for string in refused {
      XCTAssertFalse(
        DailyBriefLinkImages.isPublicDestination(URL(string: string)!), "\(string) must be refused")
    }
  }

  func testPublicHostsAreAllowed() {
    for string in ["https://example.com/a.png", "http://8.8.8.8/a.png", "https://172.32.0.1/a.png"] {
      XCTAssertTrue(
        DailyBriefLinkImages.isPublicDestination(URL(string: string)!), "\(string) must be allowed")
    }
  }

  func testRemoteFlagsAreNeverAvailable() {
    XCTAssertNil(AnalyticsService.shared.featureFlagValue("daily-brief-enabled"))
    XCTAssertNil(AnalyticsService.shared.featureFlagVariant("daily-brief-reading-first"))
  }
}

/// The summary card must be tall enough for its rating stars (label at y=380, 32pt buttons).
final class DocketSummaryCardLayoutTests: XCTestCase {
  func testSummaryCardIsTallEnoughForRatingStars() {
    XCTAssertGreaterThanOrEqual(DocketSummaryCard.height, 380 + 40 + 32)
  }
}
