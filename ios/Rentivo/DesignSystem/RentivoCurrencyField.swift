import SwiftUI

struct RentivoCurrencyField: View {
  let label: String
  @Binding var amountInCents: Int
  let errorMessage: String?
  let isFocused: Binding<Bool>?
  let isAccessibilityFocused: Binding<Bool>?
  let accessibilityIdentifier: String

  @Environment(\.isEnabled) private var isEnabled
  @State private var text: String
  @FocusState private var controlIsFocused: Bool
  @AccessibilityFocusState private var controlIsAccessibilityFocused: Bool

  init(
    label: String,
    amountInCents: Binding<Int>,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    accessibilityIdentifier: String
  ) {
    self.label = label
    _amountInCents = amountInCents
    self.errorMessage = errorMessage
    self.isFocused = isFocused
    self.isAccessibilityFocused = isAccessibilityFocused
    self.accessibilityIdentifier = accessibilityIdentifier
    _text = State(initialValue: Money(centavos: amountInCents.wrappedValue).formatted())
  }

  var body: some View {
    RentivoFormField(label: label, state: state, isFocused: controlIsFocused) {
      TextField("", text: $text)
        .keyboardType(.numberPad)
        .focused($controlIsFocused)
        .accessibilityFocused($controlIsAccessibilityFocused)
        .accessibilityLabel(label)
        .accessibilityValue(Money(centavos: amountInCents).formatted())
        .accessibilityHint(errorMessage.map { "Inválido. \($0)" } ?? "")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
    .onChange(of: text) { _, value in
      let parsed = MoneyInputRules.centavos(from: value)
      if amountInCents != parsed { amountInCents = parsed }
      let formatted = Money(centavos: parsed).formatted()
      if text != formatted { text = formatted }
    }
    .onChange(of: amountInCents) { _, value in
      guard MoneyInputRules.centavos(from: text) != value else { return }
      text = Money(centavos: value).formatted()
    }
    .onChange(of: controlIsFocused) { _, value in
      if isFocused?.wrappedValue != value { isFocused?.wrappedValue = value }
    }
    .onChange(of: isFocused?.wrappedValue ?? false) { _, value in
      if controlIsFocused != value { controlIsFocused = value }
    }
    .onChange(of: controlIsAccessibilityFocused) { _, value in
      if isAccessibilityFocused?.wrappedValue != value {
        isAccessibilityFocused?.wrappedValue = value
      }
    }
    .onChange(of: isAccessibilityFocused?.wrappedValue ?? false) { _, value in
      if controlIsAccessibilityFocused != value { controlIsAccessibilityFocused = value }
    }
  }

  private var state: RentivoFormFieldState {
    if let errorMessage { return .invalid(message: errorMessage) }
    if !isEnabled { return .disabled }
    return controlIsFocused ? .focused : .normal
  }
}

private struct RentivoCurrencyFieldPreviewContainer: View {
  @State private var amountInCents = 120_000

  var body: some View {
    VStack {
      RentivoCurrencyField(
        label: "Valor",
        amountInCents: $amountInCents,
        accessibilityIdentifier: "preview.currency"
      )
      Text("Centavos armazenados: \(amountInCents)")
    }
    .padding()
    .background(RentivoColors.paper)
  }
}

#Preview("Currency field") {
  RentivoCurrencyFieldPreviewContainer()
}
