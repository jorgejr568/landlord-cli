import RentivoCore
import SwiftUI

/// Placeholder for the Cobranças list. The real screen — the billing portfolio and its detail
/// navigation — replaces this file wholesale.
struct BillingListView: View {
  var body: some View {
    PageStateView(
      state: LoadState<String>.empty,
      emptyTitle: "Cobranças",
      emptyMessage: "A lista de cobranças para macOS chega em breve.",
      emptySystemImage: "doc.text"
    ) { _ in
      EmptyView()
    } retry: {}
    .rentivoPage()
    .navigationTitle("Cobranças")
  }
}
