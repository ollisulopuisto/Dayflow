//
//  AgentsModels.swift
//  Dayflow
//
//  Data model for the Agents tab. A headless Fable run (see AgentsRecapPrompt)
//  sweeps the day's Claude Code and Codex sessions and writes a JSON recap file
//  that decodes into these types. Every card style renders from the same
//  `turns` array — the styles are pure view-layer projections.
//
//  Decoding is deliberately lenient (decodeIfPresent + fallbacks everywhere):
//  the file is authored by a model, so a missing field or an unexpected enum
//  string should degrade gracefully instead of failing the whole recap.
//

import SwiftUI

struct AgentsDayRecap: Codable, Sendable {
  var schemaVersion: Int
  var day: String
  var generatedAt: String
  var workstreams: [AgentWorkstream]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
    day = (try? container.decodeIfPresent(String.self, forKey: .day)) ?? ""
    generatedAt = (try? container.decodeIfPresent(String.self, forKey: .generatedAt)) ?? ""
    workstreams =
      (try? container.decodeIfPresent([AgentWorkstream].self, forKey: .workstreams)) ?? []
  }

  var totalCounts: AgentStatusCounts {
    workstreams.reduce(AgentStatusCounts()) { $0.adding($1.counts) }
  }
}

struct AgentWorkstream: Codable, Identifiable, Sendable {
  var id: String
  var name: String
  var summary: String
  var bullets: [String]
  var threads: [AgentThread]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name =
      (try? container.decodeIfPresent(String.self, forKey: .name)) ?? String(localized: "Untitled")
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? name
    summary = (try? container.decodeIfPresent(String.self, forKey: .summary)) ?? ""
    bullets = (try? container.decodeIfPresent([String].self, forKey: .bullets)) ?? []
    threads = (try? container.decodeIfPresent([AgentThread].self, forKey: .threads)) ?? []
  }

  var counts: AgentStatusCounts {
    threads.reduce(AgentStatusCounts()) { $0.adding($1.status) }
  }
}

struct AgentThread: Codable, Identifiable, Sendable {
  var id: String
  var title: String
  var source: AgentThreadSource
  var projectName: String
  var sessionPath: String
  var status: AgentThreadStatus
  var startedAt: String
  var endedAt: String
  var latestOutcome: String
  var turns: [AgentTurn]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title =
      (try? container.decodeIfPresent(String.self, forKey: .title))
      ?? String(localized: "Untitled thread")
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? title
    let sourceRaw = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? ""
    source = AgentThreadSource(rawValue: sourceRaw) ?? .claude
    projectName = (try? container.decodeIfPresent(String.self, forKey: .projectName)) ?? ""
    sessionPath = (try? container.decodeIfPresent(String.self, forKey: .sessionPath)) ?? ""
    let statusRaw = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? ""
    status = AgentThreadStatus(rawValue: statusRaw) ?? .completed
    startedAt = (try? container.decodeIfPresent(String.self, forKey: .startedAt)) ?? ""
    endedAt = (try? container.decodeIfPresent(String.self, forKey: .endedAt)) ?? ""
    latestOutcome = (try? container.decodeIfPresent(String.self, forKey: .latestOutcome)) ?? ""
    turns = (try? container.decodeIfPresent([AgentTurn].self, forKey: .turns)) ?? []
  }

  var firstPrompt: String {
    turns.first(where: { $0.role == .user })?.text ?? title
  }

  /// Intermediate agent milestones: every agent turn except the one that
  /// already appears as `latestOutcome`.
  var milestoneTexts: [String] {
    let agentTexts = turns.filter { $0.role == .agent }.map(\.text)
    if agentTexts.last == latestOutcome {
      return Array(agentTexts.dropLast())
    }
    return agentTexts
  }
}

struct AgentTurn: Codable, Identifiable, Sendable {
  let id = UUID()
  var role: AgentTurnRole
  var text: String
  var highlight: AgentTurnHighlight
  var bullets: [String]
  var artifactName: String?
  var artifactPath: String?

  private enum CodingKeys: String, CodingKey {
    case role, text, highlight, bullets, artifactName, artifactPath
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let roleRaw = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? ""
    role = AgentTurnRole(rawValue: roleRaw) ?? .agent
    text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
    let highlightRaw = (try? container.decodeIfPresent(String.self, forKey: .highlight)) ?? ""
    highlight = AgentTurnHighlight(rawValue: highlightRaw) ?? .none
    bullets = (try? container.decodeIfPresent([String].self, forKey: .bullets)) ?? []
    artifactName = try? container.decodeIfPresent(String.self, forKey: .artifactName)
    artifactPath = try? container.decodeIfPresent(String.self, forKey: .artifactPath)
  }
}

enum AgentTurnRole: String, Codable, Sendable {
  case user
  case agent
}

enum AgentTurnHighlight: String, Codable, Sendable {
  case none
  case keyDecision
  case keyInfo
  case readyForReview
}

enum AgentThreadSource: String, Codable, Sendable {
  case claude
  case codex

  var displayName: String {
    switch self {
    case .claude: return String(localized: "Claude Code")
    case .codex: return String(localized: "Codex")
    }
  }
}

enum AgentThreadStatus: String, Codable, CaseIterable, Sendable {
  case blocked
  case reviewReady
  case inProgress
  case completed

  var displayName: String {
    switch self {
    case .blocked: return String(localized: "Blocked")
    case .reviewReady: return String(localized: "Review ready")
    case .inProgress: return String(localized: "In progress")
    case .completed: return String(localized: "Completed")
    }
  }
}

struct AgentStatusCounts: Sendable {
  var blocked = 0
  var reviewReady = 0
  var inProgress = 0
  var completed = 0

  func adding(_ status: AgentThreadStatus) -> AgentStatusCounts {
    var copy = self
    switch status {
    case .blocked: copy.blocked += 1
    case .reviewReady: copy.reviewReady += 1
    case .inProgress: copy.inProgress += 1
    case .completed: copy.completed += 1
    }
    return copy
  }

  func adding(_ other: AgentStatusCounts) -> AgentStatusCounts {
    var copy = self
    copy.blocked += other.blocked
    copy.reviewReady += other.reviewReady
    copy.inProgress += other.inProgress
    copy.completed += other.completed
    return copy
  }

  func count(for status: AgentThreadStatus) -> Int {
    switch status {
    case .blocked: return blocked
    case .reviewReady: return reviewReady
    case .inProgress: return inProgress
    case .completed: return completed
    }
  }
}

// MARK: - Card rendering styles

/// The four rendering sub-directions from the Figma exploration, toggleable at
/// runtime so each can be evaluated with real data.
enum AgentCardStyle: String, CaseIterable, Identifiable {
  case messenger
  case transcript
  case brief
  case milestones

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .messenger: return String(localized: "Messenger")
    case .transcript: return String(localized: "Transcript")
    case .brief:
      return String(
        localized: "Briefing",
        comment:
          "An agent milestone containing instructions or a summary; a noun, not the adjective short."
      )
    case .milestones: return String(localized: "Milestones")
    }
  }
}

// MARK: - Shared palette

enum AgentsPalette {
  private static func hex(_ value: String, alpha: CGFloat = 1) -> NSColor {
    (NSColor(hex: value) ?? .black).withAlphaComponent(alpha)
  }

  private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color.dayflowAdaptive(light: light, dark: dark)
  }

  // Soft blob fills, assigned to workstreams by index (mirrors the Figma
  // scatter: blue, purple, orange, tan, light blue). Light keeps the pastel
  // fills; dark re-tints each hue at low alpha so the blobs read as soft
  // glows instead of glaring pastel panels.
  static let blobColors: [Color] = [
    adaptive(hex("9FC1F2"), hex("5B8DEF", alpha: 0.35)),
    adaptive(hex("CBB8F5"), hex("9B7BE8", alpha: 0.35)),
    adaptive(hex("F5A25C"), hex("F3854B", alpha: 0.35)),
    adaptive(hex("DEC9B2"), hex("A98A68", alpha: 0.35)),
    adaptive(hex("B4CDF0"), hex("6E9BE8", alpha: 0.35)),
    adaptive(hex("F2B8C6"), hex("E87E9A", alpha: 0.35)),
    adaptive(hex("A8DCC5"), hex("4FB98F", alpha: 0.35)),
  ]

  static func blobColor(at index: Int) -> Color {
    blobColors[index % blobColors.count]
  }

  // Card surfaces. Light keeps the near-opaque white glass over the cream
  // canvas; dark drops to faint white overlays over the dark canvas.
  static let cardFill = adaptive(
    NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.1))
  static let cardFillSoft = adaptive(
    NSColor.white.withAlphaComponent(0.8), NSColor.white.withAlphaComponent(0.08))
  // The solid thread card: white in light, the theme's dark card color.
  static let cardSolid = adaptive(.white, hex("3A3A4C"))
  // Inset wells and footer strips inside cards.
  static let wellFill = adaptive(hex("F1EFED"), NSColor.white.withAlphaComponent(0.07))
  static let wellFillAlt = adaptive(hex("F4F3F1"), NSColor.white.withAlphaComponent(0.07))
  static let footerFill = adaptive(hex("F6F5F3"), NSColor.white.withAlphaComponent(0.05))

  // Warm accents used by the error/empty states and the review chip.
  static let errorAccent = adaptive(hex("C04A00"), hex("F3854B"))
  static let reviewBorder = adaptive(hex("F9D9BD"), hex("F3854B", alpha: 0.4))

  static func chipBackground(for status: AgentThreadStatus) -> Color {
    switch status {
    case .blocked: return adaptive(hex("FFDCDA"), hex("FC5546", alpha: 0.22))
    case .reviewReady: return adaptive(hex("CFF3E4"), hex("3FA37C", alpha: 0.25))
    case .inProgress:
      return adaptive(.white, NSColor.white.withAlphaComponent(0.14))
    case .completed:
      return adaptive(hex("ECEAE7"), NSColor.white.withAlphaComponent(0.1))
    }
  }

  static func chipForeground(for status: AgentThreadStatus) -> Color {
    switch status {
    case .blocked: return adaptive(hex("B03A31"), hex("FF9B92"))
    case .reviewReady: return adaptive(hex("1F8A6E"), hex("5ED4AC"))
    case .inProgress: return adaptive(hex("6B655F"), hex("DDDDDD"))
    case .completed: return adaptive(hex("8D8781"), hex("B4B4B4"))
    }
  }

  // Legend dots are deliberately constant: they are already light pastels
  // that read on both canvases, and the overview legend expects them to
  // match the chips' hues.
  static func legendDot(for status: AgentThreadStatus) -> Color {
    switch status {
    case .blocked: return Color(hex: "F58B84")
    case .reviewReady: return Color(hex: "5ED4AC")
    case .inProgress: return Color(hex: "FFFFFF")
    case .completed: return Color(hex: "CFCAC4")
    }
  }

  // Highlight pill colors, constant across all card styles: purple = key
  // decision, blue = key info, orange = ready for review.
  static let keyDecisionBackground = adaptive(hex("EDE4FC"), hex("9B7BE8", alpha: 0.22))
  static let keyDecisionForeground = adaptive(hex("7A4FD1"), hex("C4B0F0"))
  static let keyInfoBackground = adaptive(hex("E1ECFC"), hex("5B8DEF", alpha: 0.22))
  static let keyInfoForeground = adaptive(hex("3E76D6"), hex("9FC1F2"))
  static let reviewBackground = adaptive(hex("FFF1E5"), hex("F3854B", alpha: 0.18))
  static let reviewForeground = adaptive(hex("F96E00"), hex("F3854B"))
}

extension Color {
  /// Agents-tab ink: black in light mode, white in dark mode, same alpha, so
  /// the Figma's `.black.opacity(x)` text hierarchy inverts cleanly.
  static func agentsInk(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.white.withAlphaComponent(CGFloat(opacity))
    )
  }

  /// Hairline strokes: light keeps the Figma's faint black; dark lifts the
  /// alpha so the line stays visible against the dark canvas.
  static func agentsStroke(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.white.withAlphaComponent(CGFloat(min(opacity * 2, 0.16)))
    )
  }

  /// Drop shadows stay black in both modes but deepen in dark, matching the
  /// weekly palette's shadow treatment.
  static func agentsShadow(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.black.withAlphaComponent(0.3)
    )
  }
}
