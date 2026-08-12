import RentivoCore
import SwiftUI

/// Placeholder for the Conta screen. The real screens — profile and PIX, security, API keys, and
/// theme — replace this file wholesale.
struct AccountView: View {
  var body: some View {
    PageStateView(
      state: LoadState<String>.empty,
      emptyTitle: "Conta",
      emptyMessage: "As configurações da conta para macOS chegam em breve.",
      emptySystemImage: "person.crop.circle"
    ) { _ in
      EmptyView()
    } retry: {}
    .rentivoPage()
    .navigationTitle("Conta")
  }
}
