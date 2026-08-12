import RentivoCore
import SwiftUI

/// Placeholder for the Organizações list. The real screens — organizations, members, and pending
/// invitations — replace this file wholesale.
struct OrganizationListView: View {
  var body: some View {
    PageStateView(
      state: LoadState<String>.empty,
      emptyTitle: "Organizações",
      emptyMessage: "A gestão de organizações para macOS chega em breve.",
      emptySystemImage: "building.2"
    ) { _ in
      EmptyView()
    } retry: {}
    .rentivoPage()
    .navigationTitle("Organizações")
  }
}
