import SwiftUI

/// Places `leading` beside `trailing` when the window is wide enough for both, and stacks them
/// otherwise without constructing either column more than once.
struct BillingAdaptiveColumns<Leading: View, Trailing: View>: View {
  var breakpoint: CGFloat = 880
  var spacing: CGFloat = RentivoSpacing.section
  @ViewBuilder var leading: () -> Leading
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    BillingAdaptiveLayout(breakpoint: breakpoint, spacing: spacing) {
      VStack(alignment: .leading, spacing: RentivoSpacing.section) { leading() }
        .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        trailing()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// A single-tree adaptive container for the billing detail columns. Candidate-based containers
/// evaluate complete horizontal and vertical trees, duplicating stateful descendants such as
/// `NavigationLink`; this layout measures and places the same two subviews in either shape.
struct BillingAdaptiveLayout: Layout {
  let breakpoint: CGFloat
  let spacing: CGFloat

  static func axis(for proposedWidth: CGFloat?, breakpoint: CGFloat) -> Axis {
    guard let proposedWidth, proposedWidth.isFinite, proposedWidth >= breakpoint else {
      return .vertical
    }
    return .horizontal
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let sizes = measuredSizes(proposal: proposal, subviews: subviews)
    guard !sizes.isEmpty else { return .zero }

    switch Self.axis(for: proposal.width, breakpoint: breakpoint) {
    case .horizontal:
      return CGSize(
        width: proposal.width ?? 0,
        height: sizes.map(\.height).max() ?? 0
      )
    case .vertical:
      return CGSize(
        width: finite(proposal.width) ?? (sizes.map(\.width).max() ?? 0),
        height: sizes.map(\.height).reduce(0, +) + spacingIntervals(for: sizes.count)
      )
    }
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    switch Self.axis(for: proposal.width, breakpoint: breakpoint) {
    case .horizontal:
      let width = columnWidth(totalWidth: bounds.width, count: subviews.count)
      let childProposal = ProposedViewSize(width: width, height: nil)
      for (index, subview) in subviews.enumerated() {
        subview.place(
          at: CGPoint(
            x: bounds.minX + CGFloat(index) * (width + spacing),
            y: bounds.minY
          ),
          anchor: .topLeading,
          proposal: childProposal
        )
      }
    case .vertical:
      let childProposal = ProposedViewSize(width: bounds.width, height: nil)
      var y = bounds.minY
      for subview in subviews {
        subview.place(
          at: CGPoint(x: bounds.minX, y: y),
          anchor: .topLeading,
          proposal: childProposal
        )
        y += subview.sizeThatFits(childProposal).height + spacing
      }
    }
  }

  private func measuredSizes(proposal: ProposedViewSize, subviews: Subviews) -> [CGSize] {
    let width: CGFloat?
    switch Self.axis(for: proposal.width, breakpoint: breakpoint) {
    case .horizontal:
      width = columnWidth(totalWidth: proposal.width ?? 0, count: subviews.count)
    case .vertical:
      width = finite(proposal.width)
    }
    let childProposal = ProposedViewSize(width: width, height: nil)
    return subviews.map { $0.sizeThatFits(childProposal) }
  }

  private func columnWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return max(0, (totalWidth - spacingIntervals(for: count)) / CGFloat(count))
  }

  private func spacingIntervals(for count: Int) -> CGFloat {
    spacing * CGFloat(max(0, count - 1))
  }

  private func finite(_ width: CGFloat?) -> CGFloat? {
    guard let width, width.isFinite else { return nil }
    return width
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
