//
//  OnboardingPrototypePreferencesStep.swift
//  Dayflow
//

import SwiftUI

// MARK: - Preferences Step

struct OnboardingPrototypePreferencesStep: View {
  let onContinue: (Bool) -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      VStack(spacing: 24) {
        Text("Do you have a paid ChatGPT or Claude account?")
          .font(.custom("Figtree", size: 20))
          .foregroundColor(OnboardingPalette.subtitle)
          .multilineTextAlignment(.center)

        HStack(spacing: 8) {
          ForEach(["Yes", "No"], id: \.self) { option in
            Button {
              onContinue(option == "Yes")
            } label: {
              Text(option == "Yes" ? String(localized: "Yes") : String(localized: "No"))
                .font(.custom("Figtree", size: 16))
                .foregroundColor(OnboardingPalette.title)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(OnboardingPalette.glass(0.4, 0.08))
                .clipShape(Capsule())
                .overlay(
                  Capsule()
                    .stroke(OnboardingPalette.fieldBorder, lineWidth: 1)
                )
                .shadow(
                  color: OnboardingPalette.fieldShadow,
                  radius: 2, x: 0, y: 0
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
          }
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
