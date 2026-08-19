import SwiftUI
import UIKit

enum RentivoFormFieldState: Equatable {
  case normal
  case focused
  case invalid(message: String)
  case disabled
}

struct RentivoFormField<Control: View>: View {
  let label: String
  let hint: String?
  let state: RentivoFormFieldState
  let isFocused: Bool
  private let control: Control

  init(
    label: String,
    hint: String? = nil,
    state: RentivoFormFieldState = .normal,
    isFocused: Bool = false,
    @ViewBuilder control: () -> Control
  ) {
    self.label = label
    self.hint = hint
    self.state = state
    self.isFocused = isFocused
    self.control = control()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(RentivoTypography.metadata)
        .fontWeight(.semibold)
        .textCase(.uppercase)
        .foregroundStyle(RentivoColors.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(label)

      control
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RentivoColors.paper)
        .opacity(state == .disabled ? 0.55 : 1)
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(borderColor, lineWidth: borderWidth)
        }
        .overlay {
          if isFocusedAndInvalid {
            RoundedRectangle(cornerRadius: 15)
              .stroke(RentivoColors.emerald, lineWidth: 2)
              .padding(-4)
          }
        }

      if case .invalid(let message) = state {
        Label(message, systemImage: "exclamationmark.circle.fill")
          .font(.footnote)
          .foregroundStyle(RentivoColors.coral)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("Inválido. \(message)")
      } else if let hint {
        Text(hint)
          .font(.footnote)
          .foregroundStyle(RentivoColors.secondaryInk)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var borderColor: Color {
    switch state {
    case .focused: RentivoColors.emerald
    case .invalid: RentivoColors.coral
    case .normal, .disabled: RentivoColors.ink
    }
  }

  private var borderWidth: CGFloat {
    state == .focused ? 3 : 2
  }

  private var isFocusedAndInvalid: Bool {
    if case .invalid = state { return isFocused }
    return false
  }
}

struct RentivoTextFormField: View {
  let label: String
  @Binding var text: String
  let prompt: String?
  let axis: Axis
  let hint: String?
  let errorMessage: String?
  let isFocused: Binding<Bool>?
  let isAccessibilityFocused: Binding<Bool>?
  let accessibilityIdentifier: String

  @Environment(\.isEnabled) private var isEnabled
  @FocusState private var controlIsFocused: Bool
  @AccessibilityFocusState private var controlIsAccessibilityFocused: Bool

  init(
    label: String,
    text: Binding<String>,
    prompt: String? = nil,
    axis: Axis = .horizontal,
    hint: String? = nil,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    accessibilityIdentifier: String
  ) {
    self.label = label
    _text = text
    self.prompt = prompt
    self.axis = axis
    self.hint = hint
    self.errorMessage = errorMessage
    self.isFocused = isFocused
    self.isAccessibilityFocused = isAccessibilityFocused
    self.accessibilityIdentifier = accessibilityIdentifier
  }

  var body: some View {
    RentivoFormField(label: label, hint: hint, state: state, isFocused: controlIsFocused) {
      TextField(
        "",
        text: $text,
        prompt: prompt.map { Text($0) },
        axis: axis
      )
      .frame(minHeight: axis == .vertical ? 76 : 28, alignment: .topLeading)
      .focused($controlIsFocused)
      .accessibilityFocused($controlIsAccessibilityFocused)
      .accessibilityLabel(label)
      .accessibilityHint(accessibilityHint)
      .accessibilityIdentifier(accessibilityIdentifier)
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

  private var accessibilityHint: String {
    if let errorMessage { return "Inválido. \(errorMessage)" }
    return hint ?? ""
  }
}

struct RentivoSecureFormField: View {
  let label: String
  @Binding var text: String
  @Binding var isRevealed: Bool
  let errorMessage: String?
  let isFocused: Binding<Bool>?
  let isAccessibilityFocused: Binding<Bool>?
  let textContentType: UITextContentType
  let accessibilityIdentifier: String

  @Environment(\.isEnabled) private var isEnabled
  @FocusState private var controlIsFocused: Bool
  @AccessibilityFocusState private var controlIsAccessibilityFocused: Bool

  init(
    label: String,
    text: Binding<String>,
    isRevealed: Binding<Bool>,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    textContentType: UITextContentType,
    accessibilityIdentifier: String
  ) {
    self.label = label
    _text = text
    _isRevealed = isRevealed
    self.errorMessage = errorMessage
    self.isFocused = isFocused
    self.isAccessibilityFocused = isAccessibilityFocused
    self.textContentType = textContentType
    self.accessibilityIdentifier = accessibilityIdentifier
  }

  var body: some View {
    RentivoFormField(label: label, state: state, isFocused: controlIsFocused) {
      HStack(spacing: RentivoSpacing.small) {
        Group {
          if isRevealed {
            TextField("", text: $text)
          } else {
            SecureField("", text: $text)
          }
        }
        .textContentType(textContentType)
        .focused($controlIsFocused)
        .accessibilityFocused($controlIsAccessibilityFocused)
        .accessibilityLabel(label)
        .accessibilityHint(errorMessage.map { "Inválido. \($0)" } ?? "")
        .accessibilityIdentifier(accessibilityIdentifier)

        Button {
          let retainedFocus = controlIsFocused
          isRevealed.toggle()
          if retainedFocus {
            Task { @MainActor in controlIsFocused = true }
          }
        } label: {
          Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(revealLabel)
        .accessibilityAddTraits(isRevealed ? .isSelected : [])
        .accessibilityIdentifier("\(accessibilityIdentifier).reveal")
      }
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

  private var revealLabel: String {
    let action = isRevealed ? "Ocultar" : "Mostrar"
    switch label {
    case "Senha atual": return "\(action) senha atual"
    case "Nova senha": return "\(action) nova senha"
    case "Confirmar nova senha": return "\(action) confirmação da senha"
    default: return "\(action) \(label.lowercased())"
    }
  }
}

struct RentivoPixKeyReview: View {
  let input: PixKeyInput
  @Binding var isRevealed: Bool
  let accessibilityIdentifier: String

  var body: some View {
    RentivoWizardReviewRow(label: "Tipo da chave", value: input.type.label)
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      HStack(alignment: .firstTextBaseline, spacing: RentivoSpacing.medium) {
        Text("Chave")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
        Spacer(minLength: RentivoSpacing.medium)
        Text(isRevealed ? (input.normalizedValue ?? input.value) : input.maskedValue)
          .multilineTextAlignment(.trailing)
          .textSelection(.enabled)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Chave")
      .accessibilityValue(
        isRevealed ? "Chave PIX exibida, \(input.normalizedValue ?? input.value)"
          : input.hiddenAccessibilityValue
      )

      Button(isRevealed ? "Ocultar chave" : "Mostrar chave") {
        isRevealed.toggle()
      }
      .frame(minHeight: 44)
      .accessibilityAddTraits(isRevealed ? .isSelected : [])
      .accessibilityIdentifier(accessibilityIdentifier)
    }
  }
}

private struct RentivoFormFieldPreviewContainer: View {
  @State private var text = "Apartamento 202"
  @State private var password = "segredo"
  @State private var revealed = false

  var body: some View {
    ScrollView {
      VStack(spacing: RentivoSpacing.large) {
        RentivoTextFormField(label: "Normal", text: $text, accessibilityIdentifier: "preview.normal")
        RentivoFormField(label: "Focado", state: .focused) { TextField("", text: $text) }
        RentivoTextFormField(label: "Erro", text: $text, errorMessage: "Revise este valor.", accessibilityIdentifier: "preview.error")
        RentivoFormField(
          label: "Erro e foco",
          state: .invalid(message: "Revise este valor."),
          isFocused: true
        ) { TextField("", text: $text) }
        RentivoTextFormField(label: "Multiline", text: $text, axis: .vertical, accessibilityIdentifier: "preview.multiline")
        RentivoSecureFormField(label: "Senha atual", text: $password, isRevealed: $revealed, textContentType: .password, accessibilityIdentifier: "preview.secure")
        RentivoTextFormField(label: "Desabilitado", text: $text, accessibilityIdentifier: "preview.disabled").disabled(true)
      }
      .padding()
    }
    .background(RentivoColors.paper)
  }
}

#Preview("Form fields") {
  RentivoFormFieldPreviewContainer()
}
