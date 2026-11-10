//
//  ProviderConsentModalView.swift
//  Dayflow
//
//  Modal alarm presented the first time Dayflow is about to send data to an
//  external AI provider. Asked once per provider; "Allow" is remembered.
//

import SwiftUI

/// Invisible view that presents the provider-consent modal alarm when
/// `coordinator.isShowingModal` becomes true. Placed in the app's root ZStack.
struct ProviderConsentModalView: View {
  @ObservedObject var coordinator: ProviderConsentCoordinator

  var body: some View {
    EmptyView()
      .alert(
        modalTitle,
        isPresented: Binding(
          get: { coordinator.isShowingModal },
          set: { _ in }
        ),
        actions: {
          Button("Don't Send", role: .cancel) {
            coordinator.respond(false)
          }
          Button("Allow", role: .none) {
            coordinator.respond(true)
          }
          .buttonStyle(.borderedProminent)
        },
        message: {
          modalMessage
        }
      )
  }

  private var modalTitle: String {
    let providerName = coordinator.pendingDescriptor?.providerName ?? "an AI provider"
    return "Send Data to \(providerName)?"
  }

  private var modalMessage: Text {
    guard let descriptor = coordinator.pendingDescriptor else { return Text("") }
    return Text(
      "Dayflow is about to send \(descriptor.dataSummary) to \(descriptor.providerName) at \(descriptor.destination). Nothing is sent until you allow it. Dayflow asks this once for each provider and remembers your choice."
    )
  }
}
