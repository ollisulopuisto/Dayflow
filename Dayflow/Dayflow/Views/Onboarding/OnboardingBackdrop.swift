//
//  OnboardingBackdrop.swift
//  Dayflow
//
//  Shared onboarding background from the Figma refresh: a warm radial
//  gradient with soft clouds along the bottom edge. In dark mode the themed
//  window gradient takes over and the clouds stay home.
//

import SwiftUI

struct OnboardingBackdrop: View {
  @Environment(\.dayflowTheme) private var theme

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        if theme.isDark {
          Rectangle().fill(theme.windowBackground)
        } else {
          RadialGradient(
            stops: [
              .init(color: Color(hex: "FFE5CB"), location: 0),
              .init(color: Color(hex: "FFFBFA"), location: 0.49),
              .init(color: Color(hex: "F4F7FF"), location: 0.99),
            ],
            center: UnitPoint(x: 0.59, y: 1.0),
            startRadius: 0,
            endRadius: max(proxy.size.width, proxy.size.height) * 0.95
          )

          Image("OnboardingClouds")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: proxy.size.width)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .ignoresSafeArea()
  }
}

// MARK: - Shared palette

/// Adaptive onboarding colors. Light keeps the Figma refresh values exactly;
/// dark re-tints warm fills from the theme accent and lifts text to the
/// theme's light grays, the same convention as WeeklyPalette.
enum OnboardingPalette {
  private static func hex(_ value: String, alpha: CGFloat = 1) -> NSColor {
    (NSColor(hex: value) ?? .black).withAlphaComponent(alpha)
  }

  private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color.dayflowAdaptive(light: light, dark: dark)
  }

  // Text
  static let ink = adaptive(hex("333333"), .white)
  static let title = adaptive(hex("492304"), hex("FFE4CE"))
  static let subtitle = adaptive(hex("89380E"), hex("E2A079"))
  static let warmText = adaptive(hex("634342"), hex("D9B8A6"))
  static let brownText = adaptive(hex("926244"), hex("D9AE94"))
  static let bodyGray = adaptive(hex("727272"), hex("B3B3B3"))
  static let grayText = adaptive(hex("5B5B5B"), hex("DDDDDD"))
  static let secondaryGray = adaptive(hex("898989"), hex("B3B3B3"))
  static let mutedWarm = adaptive(hex("D0C8C2"), hex("6E6E6E"))
  static let error = adaptive(hex("E91515"), hex("FF8A80"))
  static let success = adaptive(hex("21A638"), hex("4CD97B"))

  // Status fills
  static let successFill = adaptive(hex("DEF3E0"), hex("3FA37C", alpha: 0.25))
  static let errorFill = adaptive(hex("FFD1D1"), hex("FC5546", alpha: 0.22))

  // Accents. The CTA orange stays constant across appearances.
  static let accent = Color(hex: "FF9F6F")
  static let brand = Color(hex: "F96E00")
  static let accentBorder = adaptive(hex("F4C8B1"), hex("F3854B", alpha: 0.45))
  static let accentGlow = adaptive(hex("FFDCCB"), hex("F3854B", alpha: 0.35))
  static let peachDeep = adaptive(hex("FDCEA4"), hex("F3854B", alpha: 0.3))
  static let peachFill = adaptive(hex("FFECE6"), hex("F3854B", alpha: 0.2))
  static let hairlineWarm = adaptive(hex("F1CEBC"), hex("F3854B", alpha: 0.35))

  // Neutral hairlines and grays
  static let neutralStroke = adaptive(hex("EDE5E1"), hex("4E4E4E"))
  static let coolStroke = adaptive(hex("F0F0F0"), hex("4E4E4E"))
  static let neutralGray = adaptive(hex("B6B6B6"), hex("8A8A8A"))
  static let fieldBorder = adaptive(hex("E4D3C2"), hex("6A6E84"))
  /// The warm ring shadow under the goal field (AF7246 at 15% in light).
  static let fieldShadow = adaptive(
    hex("AF7246", alpha: 0.15), NSColor.black.withAlphaComponent(0.3))

  // Translucent white cards over the backdrop become faint white overlays.
  static let cardFill = adaptive(
    NSColor.white.withAlphaComponent(0.42), NSColor.white.withAlphaComponent(0.08))
  static let cardFillMid = adaptive(
    NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0.1))
  static let cardFillStrong = adaptive(
    NSColor.white.withAlphaComponent(0.8), NSColor.white.withAlphaComponent(0.12))
  static let cardFillFaint = adaptive(
    NSColor.white.withAlphaComponent(0.3), NSColor.white.withAlphaComponent(0.06))

  // Solid panels
  static let panelFill = adaptive(
    NSColor.white.withAlphaComponent(0.9), hex("2E3040", alpha: 0.95))
  static let coolPanel = adaptive(hex("F8F9FA"), hex("2E3040"))
  static let wellPanel = adaptive(hex("FCFCFC"), hex("2E3040"))
  static let networkPanel = adaptive(hex("FFF9F4"), hex("2E3040"))

  // Setup-sidebar step chips
  static let sidebarStepFill = adaptive(hex("FFFAF8"), hex("3A3A4C"))
  static let sidebarStepBorder = adaptive(hex("FFB693"), hex("F3854B", alpha: 0.4))
  static let sidebarStepShadow = adaptive(
    hex("D5D3D9"), NSColor.black.withAlphaComponent(0.4))
}

extension Color {
  /// Onboarding ink: black in light mode, white in dark mode, same alpha.
  /// Mirrors Color.agentsInk; kept separate so each surface's palette stays
  /// self-contained until a shared helper supersedes both.
  static func onboardingInk(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.white.withAlphaComponent(CGFloat(opacity))
    )
  }

  /// Hairline strokes: light keeps the faint black; dark lifts the alpha.
  static func onboardingStroke(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.white.withAlphaComponent(CGFloat(min(opacity * 2, 0.16)))
    )
  }

  /// Drop shadows stay black in both modes but deepen in dark.
  static func onboardingShadow(_ opacity: Double) -> Color {
    Color.dayflowAdaptive(
      light: NSColor.black.withAlphaComponent(CGFloat(opacity)),
      dark: NSColor.black.withAlphaComponent(0.3)
    )
  }
}
