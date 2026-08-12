import RentivoCore
import SwiftUI

/// Placeholder for the Início dashboard. The real screen — summary cards, overdue and upcoming
/// bills, recent activity — replaces this file wholesale.
struct HomeView: View {
  var body: some View {
    PageStateView(
      state: LoadState<String>.empty,
      emptyTitle: "Início",
      emptyMessage: "O painel do Rentivo para macOS chega em breve.",
      emptySystemImage: "house"
    ) { _ in
      EmptyView()
    } retry: {}
    .rentivoPage()
    .navigationTitle("Início")
  }
}
