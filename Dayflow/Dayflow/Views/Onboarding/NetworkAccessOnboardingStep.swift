import SwiftUI

struct NetworkAccessOnboardingStep: View {
  let onBack: () -> Void
  let onContinue: () -> Void

  @State private var selectedScope = NetworkAccessStore.shared.scope

  var body: some View {
    VStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Your network, your choice")
          .font(.custom("InstrumentSerif-Regular", size: 34))
          .foregroundColor(OnboardingPalette.title)

        Text("Choose where Dayflow's own HTTP and HTTPS connections may go. You can change this anytime in Settings.")
          .font(.custom("Figtree-Medium", size: 14))
          .foregroundColor(OnboardingPalette.grayText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: 640, alignment: .leading)

      NetworkAccessScopePicker(selection: $selectedScope, appearance: .onboarding)
        .frame(maxWidth: 640)

      VStack(alignment: .leading, spacing: 10) {
        Text("Local Network permission")
          .font(.custom("Figtree-Bold", size: 13))
          .foregroundColor(OnboardingPalette.title)
        Text("macOS separately asks whether Dayflow may connect to devices on your local network. It will show that system prompt the first time Dayflow connects to a configured local service.")
          .font(.custom("Figtree-Medium", size: 12))
          .foregroundColor(OnboardingPalette.grayText)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Local Network settings") {
          NetworkAccessSystemSettings.openLocalNetworkPrivacy()
        }
        .font(.custom("Figtree-SemiBold", size: 12))
        .buttonStyle(.plain)
        .foregroundColor(OnboardingPalette.subtitle)
        .pointingHandCursor()
      }
      .frame(maxWidth: 640, alignment: .leading)
      .padding(14)
      .background(OnboardingPalette.cardFill)
      .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

      Spacer(minLength: 0)

      HStack {
        Button("Back", action: onBack)
          .buttonStyle(.plain)
          .foregroundColor(OnboardingPalette.subtitle)
        Spacer()
        Button {
          NetworkAccessStore.shared.setScope(selectedScope)
          onContinue()
        } label: {
          HStack(spacing: 6) {
            Text("Continue")
            Image(systemName: "chevron.right")
          }
          .font(.custom("Figtree-SemiBold", size: 14))
          .foregroundColor(.white)
          .padding(.horizontal, 24)
          .frame(height: 42)
          .background(OnboardingPalette.brand)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
      .frame(maxWidth: 640)
    }
    .padding(.horizontal, 48)
    .padding(.vertical, 34)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(OnboardingPalette.networkPanel)
    .onChange(of: selectedScope) { _, newScope in
      NetworkAccessStore.shared.setScope(newScope)
    }
  }
}
