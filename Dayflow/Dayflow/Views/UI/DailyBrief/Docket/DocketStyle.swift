//
//  DocketStyle.swift
//  Dayflow
//
//  Shared pieces for the "Take these off your plate" docket: the page-wide UI state
//  (prompt open, which menu or pop-up is showing), the prototype's easing curves,
//  its colors, and the button skins (Peach · Lilac pills and the round lilac buttons).
//

import SwiftUI
import AppKit

// MARK: - Shared UI state

/// State the docket shares with the rest of the brief page: the header dims while a
/// prompt is open, the dismiss pop-up sits in the page's corner, and menus draw above
/// everything so a click anywhere else can close them.
@MainActor
final class DocketUIState: ObservableObject {
  static let shared = DocketUIState()

  enum Menu: Equatable {
    case gear
    case folder(title: String)
  }

  /// The front card's prompt is open (the card is wide and lifted).
  @Published var isPromptOpen = false
  @Published var openMenu: Menu?
  /// The task the "Tell us why" pop-up asks about.
  @Published var askTitle: String?
  /// When the page last appeared, so the entrance animations share one clock.
  @Published var entranceStart = Date()
  /// The page should scroll to the top (the prompt opened).
  @Published var scrollToTopRequest = 0

  /// Escape closes menus first, then the pop-up. Returns false when nothing was open.
  func closeTopPopup() -> Bool {
    if openMenu != nil {
      openMenu = nil
      return true
    }
    if askTitle != nil {
      withAnimation(DocketMotion.ease(0.3)) { askTitle = nil }
      return true
    }
    return false
  }

  /// Seconds since the entrance started.
  func entranceElapsed(at date: Date = Date()) -> Double {
    date.timeIntervalSince(entranceStart)
  }
}

// MARK: - Motion

enum DocketMotion {
  /// `--do-ease`, used for almost every move.
  static let curve = UnitCurve.bezier(
    startControlPoint: UnitPoint(x: 0.22, y: 0.8), endControlPoint: UnitPoint(x: 0.24, y: 1))
  /// `--do-enter-ease`, used for the entrance.
  static let enterCurve = UnitCurve.bezier(
    startControlPoint: UnitPoint(x: 0.22, y: 1), endControlPoint: UnitPoint(x: 0.36, y: 1))

  static func ease(_ duration: Double) -> Animation {
    .timingCurve(0.22, 0.8, 0.24, 1, duration: duration)
  }

  static func enter(_ duration: Double) -> Animation {
    .timingCurve(0.22, 1, 0.36, 1, duration: duration)
  }

  /// The card's shrink when the prompt closes.
  static let collapse = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.6)

  /// 0…1 progress of a step that starts at `start` and lasts `duration`, through `curve`.
  static func progress(
    _ elapsed: Double, start: Double, duration: Double, curve: UnitCurve = .linear
  ) -> Double {
    let raw = min(max((elapsed - start) / duration, 0), 1)
    return curve.value(at: raw)
  }

  /// Plain linear blend between two numbers.
  static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * amount
  }
}

// MARK: - Colors

enum DocketColors {
  private static func adaptive(_ light: String, _ dark: String) -> Color {
    Color.dayflowAdaptive(
      light: NSColor(hex: light) ?? .black, dark: NSColor(hex: dark) ?? .white)
  }

  private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color.dayflowAdaptive(light: light, dark: dark)
  }

  static let ink = adaptive("333333", "FFFFFF")
  static let title = adaptive("000000", "FFFFFF")
  static let count = adaptive("9D9D9D", "B4B4B4")
  static let countHover = adaptive("6F6F6F", "DDDDDD")
  static let label = adaptive("C0B6B6", "A2A2A2")
  static let labelOpen = adaptive("C9B7B4", "A2A2A2")
  static let promptOpen = adaptive("7D7D7D", "B4B4B4")
  static let folder = Color(hex: "E08858")
  static let panel = adaptive("F1E9E7", "272A3C")
  static let divider = adaptive("ECE7E4", "4E4E4E")
  static let cardFront = adaptive("FBF5F3", "3A3A4C")
  static let cardSecond = adaptive("F8F2F1", "34364A")
  static let cardThird = adaptive("F4EDEC", "2E3044")
  static let roundFill = adaptive("D8DFF4", "4E5578")
  static let roundBorder = adaptive("D4D5D9", "6A6E84")

  // Menus and pop-ups: cream surfaces in light, the dark card family in dark.
  static let menuPanel = adaptive(
    (NSColor(hex: "FEFEFE") ?? .white).withAlphaComponent(0.85),
    (NSColor(hex: "272A3C") ?? .black).withAlphaComponent(0.92))
  static let menuBorder = adaptive("F0E5E1", "4E4E4E")
  static let popupFill = adaptive("FFFDFC", "2A2D40")
  static let popupTop = adaptive("FFFFFF", "34364A")
  static let popupBottom = adaptive("FFF8F5", "272A3C")
  static let mutedBrown = adaptive("AB8C82", "C79C8E")
  static let grayText = adaptive("8A8A8A", "B4B4B4")
  static let fieldText = adaptive("4E4E4E", "DDDDDD")

  // Card content: the prompt fade must match the card color, and the open
  // count pill and feedback text follow the surfaces they sit on.
  static let cardFade = adaptive("FFFBFA", "3A3A4C")
  static let countOpenFill = adaptive("F8F1F0", "34364A")
  static let feedbackText = adaptive("727272", "DDDDDD")
  static let editBorder = adaptive("EFE7E2", "6A6E84")

  // Summary card: peach-to-lavender in light, deepened in dark; the halo and
  // the "submitted" veil switch from white bloom to a warm glow.
  static let summaryTop = adaptive("FFE6D6", "4E3833")
  static let summaryBottom = adaptive("E8EEFF", "353C60")
  static let summaryBorder = adaptive(.white, NSColor(hex: "6A6E84") ?? .gray)
  static let summaryHalo = adaptive(.white, NSColor(hex: "F0B58E") ?? .orange)
  static let veilTop = adaptive(
    (NSColor(hex: "FFF1E8") ?? .white).withAlphaComponent(0.61),
    (NSColor(hex: "5A3F38") ?? .black).withAlphaComponent(0.7))
  static let veilMid = adaptive(
    (NSColor(hex: "EAC5BC") ?? .white).withAlphaComponent(0.61),
    (NSColor(hex: "4A3540") ?? .black).withAlphaComponent(0.7))
  static let veilBottom = adaptive(
    (NSColor(hex: "AEBEE6") ?? .white).withAlphaComponent(0.61),
    (NSColor(hex: "353C60") ?? .black).withAlphaComponent(0.7))

  // Peach · Lilac pill and round-lilac skins.
  static let pillTop = adaptive(
    NSColor(hex: "F7D5C3") ?? .white,
    (NSColor(hex: "E2A079") ?? .orange).withAlphaComponent(0.35))
  static let pillMid = adaptive(
    NSColor(hex: "F0E1DD") ?? .white,
    (NSColor(hex: "C98A6B") ?? .orange).withAlphaComponent(0.3))
  static let pillBottom = adaptive(
    NSColor(hex: "EBEEFA") ?? .white,
    (NSColor(hex: "875C46") ?? .brown).withAlphaComponent(0.35))
  static let pillGlow = adaptive(
    NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0.25))
  static let pillSheen = adaptive(
    NSColor.white.withAlphaComponent(0.85), NSColor.white.withAlphaComponent(0.3))
  static let pillBorderTop = adaptive("F7F7F9", "9A6A50")
  static let pillBorderMid = adaptive("DFE0E5", "875C46")
  static let pillBorderBottom = adaptive("D6D7DD", "6E4A3A")
  static let roundGlow = adaptive(
    NSColor.white.withAlphaComponent(0.8), NSColor.white.withAlphaComponent(0.25))

  /// The window background: peach low and slightly right of center, pale blue at the top.
  /// Dark mode uses the shared window-gradient hues (see DayflowTheme.dark).
  static var pageBackground: EllipticalGradient {
    let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
      == .darkAqua
    if isDark {
      return EllipticalGradient(
        stops: [
          .init(color: Color(hex: "303C5B"), location: 0),
          .init(color: Color(hex: "313348"), location: 0.3702),
          .init(color: Color(hex: "3B294B"), location: 0.9891),
        ],
        center: UnitPoint(x: 0.5917, y: 1),
        startRadiusFraction: 0,
        endRadiusFraction: 0.5)
    }
    return EllipticalGradient(
      stops: [
        .init(color: Color(hex: "FFE6CF"), location: 0),
        .init(color: Color(hex: "FFE6E0"), location: 0.3702),
        .init(color: Color(hex: "DAEAFC"), location: 0.9891),
      ],
      center: UnitPoint(x: 0.5917, y: 1),
      startRadiusFraction: 0,
      endRadiusFraction: 0.5)
  }
}

// MARK: - Skins

/// The Peach · Lilac pill used by Dismiss and Hand off.
struct DocketPillSkin: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(
        Capsule().fill(
          LinearGradient(
            stops: [
              .init(color: DocketColors.pillTop, location: 0),
              .init(color: DocketColors.pillMid, location: 0.5),
              .init(color: DocketColors.pillBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom))
      )
      .overlay(InnerGlow(shape: Capsule(), color: DocketColors.pillGlow, radius: 5))
      .overlay(
        Capsule()
          .inset(by: 1)
          .stroke(DocketColors.pillSheen, lineWidth: 1)
          .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
          .allowsHitTesting(false)
      )
      .overlay(
        Capsule().strokeBorder(
          LinearGradient(
            stops: [
              .init(color: DocketColors.pillBorderTop, location: 0),
              .init(color: DocketColors.pillBorderMid, location: 0.35),
              .init(color: DocketColors.pillBorderBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom),
          lineWidth: 1)
      )
  }
}

/// The round lilac skin used by Undo, the gear, the list's send button and the
/// toggle's selected segment.
struct DocketRoundSkin<S: InsettableShape>: ViewModifier {
  let shape: S
  var glow: CGFloat = 9

  func body(content: Content) -> some View {
    content
      .background(shape.fill(DocketColors.roundFill))
      .overlay(InnerGlow(shape: shape, color: DocketColors.roundGlow, radius: glow / 2))
      .overlay(shape.strokeBorder(DocketColors.roundBorder, lineWidth: 0.75))
  }
}

extension View {
  func docketPillSkin() -> some View { modifier(DocketPillSkin()) }

  func docketRoundSkin() -> some View { modifier(DocketRoundSkin(shape: Circle())) }

  /// Brightens slightly on hover and darkens while pressed, like the prototype's buttons.
  func docketHoverBrightness(_ isHovered: Bool) -> some View {
    brightness(isHovered ? 0.03 : 0)
      .animation(.easeOut(duration: 0.15), value: isHovered)
  }
}

/// A plain button style that dims a little while pressed (`brightness(0.97)`).
struct DocketPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .brightness(configuration.isPressed ? -0.03 : 0)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

// MARK: - Small icons

/// The outward arrow shown on hover next to links ("M6 6v2h8.59L5 17.59 6.41 19 16 9.41V18h2V6z").
struct DocketOutwardArrow: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 24
    var path = Path()
    let points: [CGPoint] = [
      .init(x: 6, y: 6), .init(x: 6, y: 8), .init(x: 14.59, y: 8), .init(x: 5, y: 17.59),
      .init(x: 6.41, y: 19), .init(x: 16, y: 9.41), .init(x: 16, y: 18), .init(x: 18, y: 18),
      .init(x: 18, y: 6),
    ]
    path.addLines(points.map { CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale) })
    path.closeSubpath()
    return path
  }
}

/// A docket task's people with feedback, collapsed the way the prototype does it: when a
/// summary exists, one entry per person that carries the summary instead of each note.
struct DocketFeedbackEntry: Hashable {
  var name: String
  var source: String?
  var text: String
  var url: String?
  /// True when `source` should read "Summarized from Slack" and link to `url`.
  var isSummary: Bool
}

enum DocketFeedback {
  static func entries(for item: DailyBriefDocketItem) -> [DocketFeedbackEntry] {
    let notes = item.feedback ?? []
    guard !notes.isEmpty else { return [] }
    if let summary = item.feedbackSummary, !summary.isEmpty {
      var names: [String] = []
      for note in notes where !names.contains(note.name) { names.append(note.name) }
      let url = item.feedbackUrl ?? notes.first?.url
      let source = (url ?? "").contains("slack") ? "Summarized from Slack" : "Summarized"
      return names.map { name in
        DocketFeedbackEntry(name: name, source: source, text: summary, url: url, isSummary: true)
      }
    }
    return notes.map {
      DocketFeedbackEntry(
        name: $0.name, source: $0.source, text: $0.text, url: $0.url, isSummary: false)
    }
  }

  /// Distinct people, in order, for the avatar dots.
  static func people(for item: DailyBriefDocketItem) -> [String] {
    var names: [String] = []
    for note in item.feedback ?? [] where !names.contains(note.name) { names.append(note.name) }
    return names
  }
}
