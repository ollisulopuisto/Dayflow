import SwiftUI

struct SettingsNetworkTabView: View {
  @State private var selectedScope = NetworkAccessStore.shared.scope

  var body: some View {
    SettingsSection(
      title: String(localized: "Network access"),
      subtitle: String(localized: "Choose which network destinations Dayflow may connect to."))
    {
      VStack(alignment: .leading, spacing: 16) {
        NetworkAccessScopePicker(selection: $selectedScope)

        SettingsMetadata(
          text: String(localized: "This setting limits Dayflow's HTTP and HTTPS requests. macOS separately asks whether Dayflow may access devices on your local network."))

        Button {
          NetworkAccessSystemSettings.openLocalNetworkPrivacy()
        } label: {
          HStack(spacing: 6) {
            Text(String(localized: "Open Local Network settings"))
            Image(systemName: "arrow.up.right.square")
              .font(.system(size: 11, weight: .medium))
          }
          .font(.custom("Figtree", size: 13).weight(.semibold))
          .foregroundColor(SettingsStyle.ink)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
    }
    .onChange(of: selectedScope) { _, newScope in
      NetworkAccessStore.shared.setScope(newScope)
    }
  }
}
