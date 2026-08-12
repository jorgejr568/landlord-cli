import SwiftUI

/// Places `leading` beside `trailing` when the window is wide enough for both, and stacks them
/// otherwise.
///
/// iPhone screens have one usable column, so the iOS detail screens stack every section. A macOS
/// window is freely resizable and usually far wider, so the layout is chosen from the width
/// actually offered rather than from a size class: the side-by-side branch declares `breakpoint`
/// as its minimum width, which is exactly the condition `ViewThatFits` rejects it on.
struct BillingAdaptiveColumns<Leading: View, Trailing: View>: View {
  var breakpoint: CGFloat = 880
  var spacing: CGFloat = RentivoSpacing.section
  @ViewBuilder var leading: () -> Leading
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: spacing) {
        VStack(alignment: .leading, spacing: RentivoSpacing.section) { leading() }
          .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: RentivoSpacing.section) { trailing() }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minWidth: breakpoint)

      VStack(alignment: .leading, spacing: spacing) {
        leading()
        trailing()
      }
    }
  }
}

/// Motion shared by the Cobranças and Faturas screens. Both values are deliberately short: they
/// exist to make a load or a hover feel connected to the action that caused it, not to be noticed.
enum BillingsMotion {
  /// Applied around the state assignment that publishes freshly loaded content, so rows settle in
  /// instead of popping into place.
  static let load: Animation = .spring(response: 0.34, dampingFraction: 0.86)

  /// Paired with `load` on individual rows. Computed rather than stored: `AnyTransition` is not
  /// `Sendable`, so a stored static would be shared mutable state under strict concurrency.
  static var row: AnyTransition { .opacity.combined(with: .offset(y: 8)) }
}
