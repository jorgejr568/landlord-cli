import RentivoCore
import SwiftUI

/// Placeholder shell for the macOS app. It exists so the project scaffold builds end to end and
/// proves the `RentivoCore` package links; the real navigation and features replace it.
@main
struct RentivoMacApp: App {
  var body: some Scene {
    WindowGroup {
      PlaceholderView()
    }
    .defaultSize(width: 1200, height: 760)
  }
}

/// Copy for the placeholder window, kept out of the view so tests can read it without SwiftUI.
enum PlaceholderContent {
  static let title = "Rentivo"

  /// Formats through `RentivoCore`, which is what makes this scaffold prove the package linkage.
  static var zeroBalance: String { Money.zero.formatted() }
}

struct PlaceholderView: View {
  var body: some View {
    VStack(spacing: 8) {
      Text(PlaceholderContent.title)
        .font(.largeTitle.weight(.semibold))
      Text(PlaceholderContent.zeroBalance)
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
