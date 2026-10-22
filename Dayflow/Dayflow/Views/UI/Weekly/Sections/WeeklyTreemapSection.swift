import SwiftUI

let weeklyTreemapContentCoordinateSpace = "weekly-treemap-content"

struct WeeklyTreemapSection: View {
  let snapshot: WeeklyTreemapSnapshot
  let width: CGFloat
  /// Held by reference so hovering re-renders only the hover overlay, not every
  /// category's squarified layout.
  @State private var hoverModel = WeeklyTreemapHoverModel()
  @State var drillPath: [WeeklyTreemapDrill] = []

  init(
    snapshot: WeeklyTreemapSnapshot,
    width: CGFloat = Design.sectionSize.width
  ) {
    self.snapshot = snapshot
    self.width = width
  }

  enum Design {
    static let sectionSize = CGSize(width: 958, height: 549)
    static let cornerRadius: CGFloat = 4
    static let borderColor = WeeklyPalette.cardBorder
    @MainActor static var background: Color { WeeklyPalette.cardFill }
    static let titleOrigin = CGPoint(x: 40, y: 34)
    static let contentOrigin = CGPoint(x: 40, y: 86)
    static let contentTrailingInset: CGFloat = 40
    static let contentSize = CGSize(width: 797, height: 400)
    static let categoryGap: CGFloat = 6
    static let hoverCardSize = CGSize(width: 176, height: 92)
    static let hoverCardGap: CGFloat = 10
  }

  private var contentWidth: CGFloat {
    max(Design.contentSize.width, width - Design.contentOrigin.x - Design.contentTrailingInset)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        .fill(Design.background)

      Text(snapshot.title)
        .font(.custom("InstrumentSerif-Regular", size: 20))
        .foregroundStyle(WeeklyPalette.title)
        .offset(x: Design.titleOrigin.x, y: Design.titleOrigin.y)

      contentLayer
        .frame(width: contentWidth, height: Design.contentSize.height)
        .offset(x: Design.contentOrigin.x, y: Design.contentOrigin.y)
    }
    .frame(width: width, height: Design.sectionSize.height)
    .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        .stroke(Design.borderColor, lineWidth: 1)
    )
  }

  @ViewBuilder
  var contentLayer: some View {
    if let drill = drillPath.last {
      WeeklyTreemapDrillView(
        drill: drill,
        onOpen: { drillPath.append($0) },
        onBack: { drillPath.removeLast() }
      )
    } else {
      categoryTreemap
    }
  }

  var categoryTreemap: some View {
    GeometryReader { proxy in
      let placements = SquarifiedTreemapLayout.place(
        snapshot.categories,
        value: { $0.weight },
        order: WeeklyTreemapCategory.displayOrder,
        in: CGRect(origin: .zero, size: proxy.size),
        gap: Design.categoryGap
      )

      ZStack(alignment: .topLeading) {
        ForEach(placements) { placement in
          WeeklyTreemapCategoryCard(
            category: placement.item,
            onLeafHover: { state in
              withAnimation(.easeOut(duration: 0.14)) {
                hoverModel.hoveredLeaf = state
              }
            },
            onOpen: { drill in
              hoverModel.hoveredLeaf = nil
              drillPath.append(drill)
            }
          )
          .frame(width: placement.frame.width, height: placement.frame.height)
          .offset(x: placement.frame.minX, y: placement.frame.minY)
        }

        WeeklyTreemapHoverOverlay(
          model: hoverModel,
          cardSize: Design.hoverCardSize,
          origin: { frame in hoverCardOrigin(for: frame, in: proxy.size) }
        )
        .zIndex(10)
        .allowsHitTesting(false)
      }
      .coordinateSpace(name: weeklyTreemapContentCoordinateSpace)
    }
  }

  func hoverCardOrigin(for frame: CGRect, in size: CGSize) -> CGPoint {
    let cardWidth = Design.hoverCardSize.width
    let cardHeight = Design.hoverCardSize.height

    let centeredX = frame.midX - (cardWidth / 2)
    let x = min(max(centeredX, 0), size.width - cardWidth)

    let preferredAboveY = frame.minY - cardHeight - Design.hoverCardGap
    if preferredAboveY >= 0 {
      return CGPoint(x: x, y: preferredAboveY)
    }

    let belowY = frame.maxY + Design.hoverCardGap
    let clampedBelowY = min(belowY, size.height - cardHeight)
    return CGPoint(x: x, y: max(clampedBelowY, 0))
  }
}

final class WeeklyTreemapHoverModel: ObservableObject {
  @Published var hoveredLeaf: WeeklyTreemapHoverState?
}

/// The only view that observes hover, so moving the mouse across tiles leaves the layout alone.
private struct WeeklyTreemapHoverOverlay: View {
  @ObservedObject var model: WeeklyTreemapHoverModel
  let cardSize: CGSize
  let origin: (CGRect) -> CGPoint

  var body: some View {
    if let hoveredLeaf = model.hoveredLeaf {
      let point = origin(hoveredLeaf.frame)
      WeeklyTreemapHoverCard(app: hoveredLeaf.app, palette: hoveredLeaf.palette)
        .frame(width: cardSize.width, height: cardSize.height)
        .offset(x: point.x, y: point.y)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
    }
  }
}
