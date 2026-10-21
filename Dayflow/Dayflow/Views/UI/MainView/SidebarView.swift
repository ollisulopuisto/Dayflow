import SwiftUI

private enum SidebarMetrics {
  static let itemSpacing: CGFloat = 5.25
  static let scale: CGFloat = 1.1
  static let itemSize: CGFloat = 56 * scale
  static let selectedBackgroundSize: CGFloat = 30 * scale
  static let selectedBackgroundRadius: CGFloat = 10
  static let iconSize: CGFloat = 16 * scale
  static let fallbackSymbolSize: CGFloat = 15 * scale
  static let badgeSize: CGFloat = 8 * scale
  static let badgeOffsetX: CGFloat = 10 * scale
  static let badgeOffsetY: CGFloat = -10 * scale
  static let iconContainerSize: CGFloat = 34 * scale
  static let iconLabelSpacing: CGFloat = 3
  static let labelFontSize: CGFloat = 11 * scale
}

extension SidebarIcon {
  /// Sections reachable with Cmd+1 ... Cmd+6, in sidebar order.
  static func forCommandNumber(_ number: Int) -> SidebarIcon? {
    switch number {
    case 1: return .timeline
    case 2: return .daily
    case 3: return .weekly
    case 4: return .chat
    case 5: return .flow
    case 6: return .agents
    default: return nil
    }
  }
}

enum SidebarIcon: CaseIterable {
  case timeline
  case daily
  case weekly
  case chat
  case flow
  case agents
  case bug
  case settings

  var assetName: String? {
    switch self {
    case .timeline: return "TimelineIcon"
    case .daily: return "DailyIcon"
    case .weekly: return "WeeklyIcon"
    case .chat: return "ChatIcon"
    case .flow: return "FlowIcon"
    case .agents: return "AgentsIcon"
    case .bug: return nil
    case .settings: return nil
    }
  }

  var systemNameFallback: String? {
    switch self {
    case .flow: return "water.waves"
    case .agents: return "sparkles"
    case .bug: return "exclamationmark.bubble.fill"
    case .settings: return "gearshape.fill"
    default: return nil
    }
  }

  var displayName: String {
    switch self {
    case .timeline: return String(localized: "Timeline")
    case .daily:
      return String(
        localized: "sidebar.daily", defaultValue: "Daily",
        comment: "Short sidebar label for the daily recap view.")
    case .weekly:
      return String(
        localized: "sidebar.weekly", defaultValue: "Weekly",
        comment: "Short sidebar label for the weekly recap view.")
    case .chat: return String(localized: "Chat")
    case .flow: return String(localized: "Flow")
    case .agents: return String(localized: "Agents")
    case .bug: return String(localized: "Support")
    case .settings: return String(localized: "Settings")
    }
  }

  var analyticsTabName: String {
    switch self {
    case .timeline: return "timeline"
    case .daily: return "daily"
    case .weekly: return "weekly"
    case .chat: return "dashboard"
    case .flow: return "flow"
    case .agents: return "agents"
    case .bug: return "bug_report"
    case .settings: return "settings"
    }
  }
}

extension SidebarIcon {
  /// Flow is hidden from the sidebar unless the user turns "Show Flow" on in Settings > Other.
  static let hideFlowKey = "hideFlowInSidebar"

  static var hidesFlowByDefault: Bool {
    UserDefaults.standard.object(forKey: hideFlowKey) as? Bool ?? true
  }

  static func visibleIcons(hideFlow: Bool) -> [SidebarIcon] {
    allCases.filter { !(hideFlow && $0 == .flow) }
  }

  /// The Cmd+number that selects this section, if it has one.
  var commandNumber: Int? {
    switch self {
    case .timeline: return 1
    case .daily: return 2
    case .weekly: return 3
    case .chat: return 4
    case .flow: return 5
    case .agents: return 6
    default: return nil
    }
  }

  /// Tooltip text that also shows the keyboard shortcut.
  var shortcutHint: String {
    if self == .settings { return "\(displayName) (⌘,)" }
    guard let number = commandNumber else { return displayName }
    return "\(displayName) (⌘\(number))"
  }
}

struct SidebarView: View {
  @Binding var selectedIcon: SidebarIcon
  @ObservedObject private var badgeManager = NotificationBadgeManager.shared
  @AppStorage(SidebarIcon.hideFlowKey) private var hideFlow = true

  var body: some View {
    VStack(alignment: .center, spacing: SidebarMetrics.itemSpacing) {
      ForEach(SidebarIcon.visibleIcons(hideFlow: hideFlow), id: \.self) { icon in
        SidebarIconButton(
          icon: icon,
          isSelected: selectedIcon == icon,
          showBadge: shouldShowBadge(for: icon),
          action: { selectedIcon = icon }
        )
        .frame(width: SidebarMetrics.itemSize, height: SidebarMetrics.itemSize)
        .help(icon.shortcutHint)
      }
    }
  }

  private func shouldShowBadge(for icon: SidebarIcon) -> Bool {
    switch icon {
    case .bug:
      return badgeManager.supportUnreadCount > 0
    case .flow:
      return badgeManager.flowWaitlistUnreadCount > 0
    case .daily:
      return badgeManager.hasPendingDailyRecap
    default:
      return false
    }
  }
}

struct SidebarIconButton: View {
  @Environment(\.dayflowTheme) private var theme

  let icon: SidebarIcon
  let isSelected: Bool
  var showBadge: Bool = false
  let action: () -> Void

  private var iconColor: Color {
    isSelected ? theme.sidebarIconActive : theme.sidebarIcon
  }

  private var labelColor: Color {
    isSelected ? theme.sidebarLabelActive : theme.sidebarLabel
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: SidebarMetrics.iconLabelSpacing) {
        iconBox

        Text(icon.displayName)
          .font(.custom("Figtree", size: SidebarMetrics.labelFontSize))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .foregroundColor(labelColor)
      }
      .frame(width: SidebarMetrics.itemSize, height: SidebarMetrics.itemSize)
      .contentShape(Rectangle())
    }
    .buttonStyle(DayflowPressScaleButtonStyle())
    .contentShape(Rectangle())
    .hoverScaleEffect(scale: 1.02)
    .pointingHandCursor()
  }

  private var iconBox: some View {
    let shape = RoundedRectangle(
      cornerRadius: SidebarMetrics.selectedBackgroundRadius, style: .continuous)

    return ZStack {
      if isSelected {
        shape
          .fill(theme.sidebarSelectedFill)
          .overlay(InnerGlow(shape: shape, color: theme.sidebarSelectedInnerGlow, radius: 3))
          .overlay(shape.strokeBorder(theme.sidebarSelectedBorder, lineWidth: 0.58))
          .shadow(color: theme.sidebarSelectedShadow, radius: 2, x: 0, y: 1)
          .frame(
            width: SidebarMetrics.selectedBackgroundSize,
            height: SidebarMetrics.selectedBackgroundSize
          )
      }

      iconImage
        .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)

      if showBadge {
        Circle()
          .fill(theme.accent)
          .frame(width: SidebarMetrics.badgeSize, height: SidebarMetrics.badgeSize)
          .offset(x: SidebarMetrics.badgeOffsetX, y: SidebarMetrics.badgeOffsetY)
      }
    }
    .frame(width: SidebarMetrics.iconContainerSize, height: SidebarMetrics.iconContainerSize)
  }

  @ViewBuilder
  private var iconImage: some View {
    if let asset = icon.assetName {
      Image(asset)
        .resizable()
        .interpolation(.high)
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .foregroundColor(iconColor)
    } else if let sys = icon.systemNameFallback {
      Image(systemName: sys)
        .font(.system(size: SidebarMetrics.fallbackSymbolSize))
        .foregroundColor(iconColor)
    }
  }
}
