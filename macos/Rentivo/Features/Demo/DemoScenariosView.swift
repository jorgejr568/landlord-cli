import RentivoCore
import SwiftUI

/// Placeholder for the Cenários screen, which drives the demo store's delay, empty, viewer, and
/// failure toggles. The real screen replaces this file wholesale.
struct DemoScenariosView: View {
  var body: some View {
    PageStateView(
      state: LoadState<String>.empty,
      emptyTitle: "Cenários",
      emptyMessage: "Os cenários de demonstração para macOS chegam em breve.",
      emptySystemImage: "wand.and.stars"
    ) { _ in
      EmptyView()
    } retry: {}
    .rentivoPage()
    .navigationTitle("Cenários")
  }
}
