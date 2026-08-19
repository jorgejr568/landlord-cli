import SwiftUI

/// A text field that edits an `Int` centavos value as pt-BR currency, e.g. typing
/// "245000" displays "R$ 2.450,00". The bound value is always parsed from the typed
/// digits into an `Int` — the field never touches `Double`/`Float` for the amount
/// itself (display formatting alone goes through `Money.formatted()`, which uses
/// `Decimal`, mirroring the rest of the app).
///
/// Replaces the ad hoc `TextField("Valor em centavos", value:, format: .number)`
/// pattern used across screens today, which forced users to type raw centavos.
struct CurrencyCentavosField: View {
  private let label: String
  @Binding private var centavos: Int
  private let isFocused: Binding<Bool>?
  private let isAccessibilityFocused: Binding<Bool>?
  @State private var text: String
  @FocusState private var textFieldIsFocused: Bool
  @AccessibilityFocusState private var textFieldIsAccessibilityFocused: Bool

  /// - Parameters:
  ///   - label: Visible placeholder and accessibility label for the field.
  ///   - centavos: The bound integer amount, in centavos.
  init(
    _ label: String,
    centavos: Binding<Int>,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil
  ) {
    self.label = label
    self._centavos = centavos
    self.isFocused = isFocused
    self.isAccessibilityFocused = isAccessibilityFocused
    self._text = State(initialValue: Self.format(centavos.wrappedValue))
  }

  var body: some View {
    TextField(label, text: $text)
      .keyboardType(.numberPad)
      .focused($textFieldIsFocused)
      .accessibilityFocused($textFieldIsAccessibilityFocused)
      .accessibilityLabel(label)
      .onChange(of: text) { _, newValue in
        let parsed = MoneyInputRules.centavos(from: newValue)
        if parsed != centavos {
          centavos = parsed
        }
        let formatted = Self.format(parsed)
        if formatted != text {
          text = formatted
        }
      }
      .onChange(of: centavos) { _, newValue in
        // Typing already wrote the formatted text above, and this fires right after with
        // the value that text encodes; formatting again would only rebuild the identical
        // string. Comparing the digits skips that, leaving only external value changes
        // (a parent rewriting the binding) to reformat.
        guard MoneyInputRules.centavos(from: text) != newValue else { return }
        text = Self.format(newValue)
      }
      .onChange(of: textFieldIsFocused) { _, newValue in
        guard isFocused?.wrappedValue != newValue else { return }
        isFocused?.wrappedValue = newValue
      }
      .onChange(of: isFocused?.wrappedValue ?? false) { _, newValue in
        guard textFieldIsFocused != newValue else { return }
        textFieldIsFocused = newValue
      }
      .onChange(of: textFieldIsAccessibilityFocused) { _, newValue in
        guard isAccessibilityFocused?.wrappedValue != newValue else { return }
        isAccessibilityFocused?.wrappedValue = newValue
      }
      .onChange(of: isAccessibilityFocused?.wrappedValue ?? false) { _, newValue in
        guard textFieldIsAccessibilityFocused != newValue else { return }
        textFieldIsAccessibilityFocused = newValue
      }
  }

  private static func format(_ centavos: Int) -> String {
    Money(centavos: centavos).formatted()
  }
}

private struct CurrencyCentavosFieldPreviewContainer: View {
  @State private var centavos = 245_000

  var body: some View {
    Form {
      CurrencyCentavosField("Valor da parcela", centavos: $centavos)
      Text("Centavos armazenados: \(centavos)")
        .font(.caption)
        .foregroundStyle(RentivoColors.secondaryInk)
    }
  }
}

#Preview("CurrencyCentavosField") {
  CurrencyCentavosFieldPreviewContainer()
}
