import SwiftUI

extension View {
  /// Pointer feedback for a whole surface that acts as a button — a card link or a list row.
  /// macOS has no touch feedback, so the pointer response is the only thing that makes the
  /// surface read as clickable at all. `elevated` adds a soft accent glow for surfaces that
  /// stand on their own card and can afford to lift off the page.
  func rentivoHoverLift(elevated: Bool = false) -> some View {
    modifier(RentivoHoverLift(elevated: elevated))
  }

  /// Pointer feedback for a row that lives inside a card, where a scale would fight the card's
  /// own border: the row tints instead, to show it carries an action.
  func rentivoHoverTint(cornerRadius: CGFloat = 10) -> some View {
    modifier(RentivoHoverTint(cornerRadius: cornerRadius))
  }

  /// Explicit sizing every sheet in the app adopts. macOS sheets have no natural size of their
  /// own: without this a `Form` sheet opens as a narrow sliver of its content.
  func rentivoSheetFrame() -> some View {
    frame(minWidth: 640, idealWidth: 720, minHeight: 520)
  }
}

private struct RentivoHoverLift: ViewModifier {
  let elevated: Bool
  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(isHovering ? 1.01 : 1)
      .shadow(
        color: RentivoColors.emerald.opacity(elevated && isHovering ? 0.35 : 0),
        radius: 10,
        x: 0,
        y: 4
      )
      .animation(.easeOut(duration: 0.12), value: isHovering)
      .onHover { isHovering = $0 }
  }
}

private struct RentivoHoverTint: ViewModifier {
  let cornerRadius: CGFloat
  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(RentivoColors.emerald.opacity(isHovering ? 0.10 : 0))
      )
      .animation(.easeOut(duration: 0.12), value: isHovering)
      .onHover { isHovering = $0 }
  }
}

extension Binding where Value == Bool {
  /// Drives a presentation (`sheet`, `alert`, `confirmationDialog`) from the optional value it
  /// presents: `true` while a value is set, and clearing that value when the presentation
  /// closes. Only dismissal is ever pushed back by SwiftUI, so setting `true` here is a no-op —
  /// assigning the value is what opens the presentation.
  init<Wrapped>(presence value: Binding<Wrapped?>) {
    self.init(
      get: { value.wrappedValue != nil },
      set: { isPresented in if !isPresented { value.wrappedValue = nil } }
    )
  }
}
