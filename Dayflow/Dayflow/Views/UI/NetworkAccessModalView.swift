//
//  NetworkAccessModalView.swift
//  Dayflow
//
//  Modal alarm presented when a connection requires a wider scope than the
//  user selected in Settings or onboarding.
//

import SwiftUI

/// Invisible view that presents the network-permission modal alarm when
/// `coordinator.isShowingModal` becomes true. Placed in the app's root ZStack.
struct NetworkAccessModalView: View {
  @ObservedObject var coordinator: NetworkAccessCoordinator

  var body: some View {
    EmptyView()
      .alert(
        "Network Access Needed",
        isPresented: Binding(
          get: { coordinator.isShowingModal },
          set: { _ in }
        ),
        actions: {
          Button("Don't Allow", role: .cancel) {
            coordinator.respond(false)
          }
          Button("Allow \(coordinator.pendingScope.title)", role: .none) {
            coordinator.respond(true)
          }
          .buttonStyle(.borderedProminent)
        },
        message: {
          modalMessage
        }
      )
  }

  private var modalMessage: Text {
    let host = coordinator.pendingURL?.host ?? "an external service"
    return Text(
      "Dayflow tried to connect to \(host), which is outside your current network access scope. This request may send data to that host. Allow \(coordinator.pendingScope.title.lowercased()) access?"
    )
  }
}
