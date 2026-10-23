import SwiftUI

enum TimelineScale {
  static let hourHeight: CGFloat = 168
}

enum TimelineCardLayout {
  static let iconLeadingInset: CGFloat = 16
  static let iconTextSpacing: CGFloat = 6
  static let faviconSize: CGFloat = 18
  static let faviconVerticalOffset: CGFloat = 0
  static let compactDurationThreshold: CGFloat = 13
  static let compactVerticalPadding: CGFloat = 0
  static let normalVerticalPadding: CGFloat = 6
  static let hoverScale: CGFloat = 1.005
  static let pressedScale: CGFloat = 0.992
}

enum TimelineTypography {
  static let cardTextFontSize: CGFloat = 16
  static let cardTextFontWeight: TimelineCardTextWeight = .regular
  static let timeLabelFontSize: CGFloat = 12

  static func cardSecondaryTextFontSize(for cardTextFontSize: CGFloat) -> CGFloat {
    max(8, cardTextFontSize - 3)
  }
}

enum TimelineCardTextWeight: String, CaseIterable, Identifiable {
  case regular
  case medium
  case semibold
  case bold

  var id: String { rawValue }

  var label: String {
    switch self {
    case .regular:
      return String(localized: "Reg")
    case .medium:
      return String(localized: "Med")
    case .semibold:
      return String(localized: "Semi")
    case .bold:
      return String(localized: "Bold")
    }
  }

  var fontWeight: Font.Weight {
    switch self {
    case .regular:
      return .regular
    case .medium:
      return .medium
    case .semibold:
      return .semibold
    case .bold:
      return .bold
    }
  }
}

/// Which cards are worth building while scrolling. Cards are absolutely positioned, so only the
/// scroll position is needed. It is quantized into buckets so state changes once per
/// `bucketSize` points of scrolling, not once per frame.
enum TimelineCardWindow {
  static let bucketSize: CGFloat = 300
  /// Extra space kept above and below the viewport so cards are there before they scroll in.
  static let margin: CGFloat = 300
  static let minimumViewportHeight: CGFloat = 800

  /// `layerMinY` is the cards layer top in the timeline pane: it goes negative as you scroll down.
  static func bucket(layerMinY: CGFloat) -> Int {
    Int((max(0, -layerMinY) / bucketSize).rounded(.down))
  }

  static func viewportHeight(windowContentHeight: CGFloat?) -> CGFloat {
    max(minimumViewportHeight, windowContentHeight ?? 0)
  }

  /// A band in layer coordinates. The bucket reads the offset from the layer's top in the pane,
  /// which is the real scroll offset minus the header above it (under 300 pt), so the band
  /// starts a margin early and runs a bucket plus two margins past the viewport.
  static func range(bucket: Int, viewportHeight: CGFloat) -> ClosedRange<CGFloat> {
    let top = CGFloat(bucket) * bucketSize - margin
    return top...(top + viewportHeight + bucketSize + 2 * margin)
  }

  static func isVisible(y: CGFloat, height: CGFloat, in range: ClosedRange<CGFloat>) -> Bool {
    y + height >= range.lowerBound && y <= range.upperBound
  }
}

/// Whether a full-width card overlaps the weekly-hours footer, by vertical span only.
/// Callers have already checked that the footer intersects the cards layer.
enum TimelineFooterOverlap {
  static func overlaps(cardY: CGFloat, height: CGFloat, footer: CGRect) -> Bool {
    cardY < footer.maxY && cardY + height > footer.minY
  }
}

/// Hour label frames derived from the one measured time column, so a scroll frame reports
/// a single frame instead of one per label.
enum TimelineTimeLabelGeometry {
  static func frames(
    column: CGRect, count: Int, hourHeight: CGFloat, labelHeight: CGFloat, yOffset: CGFloat
  ) -> [CGRect] {
    (0..<count).map { index in
      CGRect(
        x: column.minX, y: column.minY + CGFloat(index) * hourHeight + yOffset,
        width: column.width, height: labelHeight)
    }
  }
}

struct TimelineTimeLabelFramesPreferenceKey: PreferenceKey {
  static var defaultValue: [CGRect] = []

  static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
    value.append(contentsOf: nextValue())
  }
}
