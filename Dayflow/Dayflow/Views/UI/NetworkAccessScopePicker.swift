import AppKit
import SwiftUI

struct NetworkAccessScopePicker: View {
  enum Appearance: Equatable {
    case settings
    case onboarding
  }

  @Binding var selection: NetworkAccessScope
  var appearance: Appearance = .settings

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(NetworkAccessScope.allCases) { scope in
        Button {
          selection = scope
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: selection == scope ? "largecircle.fill.circle" : "circle")
              .font(.system(size: 16))
              .foregroundColor(selection == scope ? accent : secondaryText)
              .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
              Text(scope.title)
                .font(.custom("Figtree", size: appearance == .onboarding ? 14 : 13))
                .fontWeight(.semibold)
                .foregroundColor(primaryText)
              Text(scope.detail)
                .font(.custom("Figtree", size: 12))
                .foregroundColor(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(selection == scope ? selectedFill : Color.clear)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(selection == scope ? accent.opacity(0.5) : border, lineWidth: 1)
          )
          .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var accent: Color {
    appearance == .settings ? SettingsStyle.ink : Color(hex: "F96E00")
  }

  private var primaryText: Color {
    appearance == .settings ? SettingsStyle.text : Color(hex: "492304")
  }

  private var secondaryText: Color {
    appearance == .settings ? SettingsStyle.secondary : Color(hex: "5B5B5B")
  }

  private var selectedFill: Color {
    appearance == .settings ? SettingsStyle.subtleFill : Color.white.opacity(0.42)
  }

  private var border: Color {
    appearance == .settings ? SettingsStyle.divider : Color(hex: "89380E").opacity(0.18)
  }
}

enum NetworkAccessSystemSettings {
  static func openLocalNetworkPrivacy() {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
