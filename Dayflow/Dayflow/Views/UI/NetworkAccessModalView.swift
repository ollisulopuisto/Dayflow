//
//  NetworkAccessModalView.swift
//  Dayflow
//
//  Modal alarm presented the first time the app attempts outside (non-localhost)
//  network access. Dayflow is local-first: nothing leaves the machine unless the
//  user explicitly taps "Allow". Tapping "Don't Allow" denies the request and
// keeps the local-only default.
//

import SwiftUI

/// Invisible view that presents the network-permission modal alarm when
/// `coordinator.isShowingModal` becomes true. Placed in the app's root ZStack.
struct NetworkAccessModalView: View {
  @ObservedObject var coordinator: NetworkAccessCoordinator

  var body: some View {
    EmptyView()
      .alert(
        "Outside Network Access Blocked",
        isPresented: $coordinator.isShowingModal,
        actions: {
          Button("Don't Allow", role: .cancel) {
            coordinator.respond(false)
          }
          Button("Allow", role: .none) {
            coordinator.respond(true)
          }
          .buttonStyle(.borderedProminent)
        },
        message: {
          Text(modalMessage)
        }
      )
  }

  private var modalMessage: Text {
    let host = coordinator.pendingURL?.host ?? "an external service"
    return Text(
      """
      Dayflow is local-first and does not send your data anywhere by default.

      Dayflow tried to connect to \(host).

      Allow outside network access? This may send data to \(host).
      """
    )
  }
}
