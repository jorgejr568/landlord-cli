import SwiftUI

enum ThemeWizardRules {
  static let invalidColorMessage = "Use uma cor hexadecimal no formato #RRGGBB."

  static func colorValidationMessage(_ value: String) -> String? {
    value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) == nil
      ? invalidColorMessage : nil
  }

  static func loadedValuesToApply(
    _ loaded: ThemeValues,
    requestDraft: ThemeValues,
    currentDraft: ThemeValues,
    requestDraftRevision: Int,
    currentDraftRevision: Int
  ) -> ThemeValues? {
    RentivoAsyncDraftLoadRules.shouldApply(
      requestDraft: requestDraft,
      currentDraft: currentDraft,
      requestRevision: requestDraftRevision,
      currentRevision: currentDraftRevision
    ) ? loaded : nil
  }
}

private enum ThemeWizardField: Hashable {
  case primary
  case primaryLight
  case secondary
  case secondaryDark
  case textColor
  case textContrast

  var accessibilityIdentifier: String {
    switch self {
    case .primary: "primary"
    case .primaryLight: "primary-light"
    case .secondary: "secondary"
    case .secondaryDark: "secondary-dark"
    case .textColor: "text"
    case .textContrast: "text-contrast"
    }
  }
}

struct ThemeEditorView: View {
  private enum Step: CaseIterable {
    case typography
    case primaryColors
    case textAndContrast
    case preview
    case review
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let target: ThemeTarget
  @State private var record: ThemeRecord?
  @State private var values = ThemeValues.rentivo
  @State private var loadedValues: ThemeValues?
  @State private var error: DemoError?
  @State private var step: Step = .typography
  @State private var saving = false
  @State private var validationMessage: String?
  @State private var resetRequested = false
  @State private var draftRevision = 0
  @State private var themeLoaded = false
  @State private var readinessMessage: String?
  @FocusState private var focusedField: ThemeWizardField?
  @AccessibilityFocusState private var accessibilityFocusedField: ThemeWizardField?

  /// True once the user has changed a field since the last successful load/save.
  /// Guards against `.task(id:)` reloads (triggered by unrelated `app.dataRevision`
  /// bumps) silently overwriting in-progress, unsaved color edits.
  private var isDirty: Bool {
    resetRequested || values != (loadedValues ?? .rentivo)
  }

  var body: some View {
    RentivoFormWizard(
      title: "Aparência",
      descriptors: descriptors,
      selectedStep: $step,
      isBusy: saving,
      isPrimaryEnabled: RentivoAsyncDraftLoadRules.isPrimaryEnabled(
        hasLoadedBaseline: themeLoaded
      ),
      finalActionTitle: finalActionTitle,
      onValidateAndAdvance: validateCurrentStep,
      onCommit: commit
    ) { selectedStep in
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        stepContent(selectedStep)
          .disabled(!themeLoaded)
        if let readinessMessage {
          RentivoWizardSection("Tema indisponível") {
            validationLabel(readinessMessage)
            Button("Tentar novamente") { Task { await load() } }
              .accessibilityIdentifier("theme.form.retry")
          }
        }
      }
    }
    .interactiveDismissDisabled(isDirty || saving)
    .task(id: app.dataRevision) {
      guard !isDirty else { return }
      await load()
    }
    .onChange(of: values) {
      draftRevision &+= 1
      if resetRequested { resetRequested = false }
    }
    .alert(
      "Não foi possível atualizar",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("Tentar novamente") {
        error = nil
        Task { await load() }
      }
      Button("Cancelar", role: .cancel) { error = nil }
    } message: {
      Text(error?.message ?? "")
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .typography, title: "Tipografia"),
      .init(id: .primaryColors, title: "Cores principais"),
      .init(id: .textAndContrast, title: "Texto e contraste"),
      .init(id: .preview, title: "Prévia"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var finalActionTitle: String {
    guard themeLoaded else { return "Carregando tema…" }
    guard record?.canEdit == true else { return "Concluir" }
    return resetRequested ? "Restaurar tema" : "Salvar tema"
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .typography:
      RentivoWizardSection(
        "Tipografia da marca",
        subtitle: "Escolha fontes para títulos e textos dos documentos."
      ) {
        Picker("Fonte de títulos", selection: $values.headerFont) {
          ForEach(ThemeFont.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("theme.form.header-font")
        Picker("Fonte de texto", selection: $values.textFont) {
          ForEach(ThemeFont.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .accessibilityIdentifier("theme.form.text-font")
      }
    case .primaryColors:
      RentivoWizardSection(
        "Cores principais",
        subtitle: "Informe cores hexadecimais usadas nos destaques da marca."
      ) {
        ThemeColorField(
          title: "Primária", value: $values.primary, field: .primary,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        ThemeColorField(
          title: "Primária clara", value: $values.primaryLight, field: .primaryLight,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        ThemeColorField(
          title: "Secundária", value: $values.secondary, field: .secondary,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        if let validationMessage { validationLabel(validationMessage) }
      }
    case .textAndContrast:
      RentivoWizardSection(
        "Texto e contraste",
        subtitle: "Ajuste superfícies escuras e a legibilidade do texto."
      ) {
        ThemeColorField(
          title: "Secundária escura", value: $values.secondaryDark, field: .secondaryDark,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        ThemeColorField(
          title: "Texto", value: $values.textColor, field: .textColor,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        ThemeColorField(
          title: "Texto de contraste", value: $values.textContrast, field: .textContrast,
          focusedField: $focusedField,
          accessibilityFocusedField: $accessibilityFocusedField
        )
        if let validationMessage { validationLabel(validationMessage) }
      }
    case .preview:
      inheritanceSection
      RentivoWizardSection(
        "Prévia ao vivo",
        subtitle: "A visualização muda enquanto você edita as cores."
      ) {
        ThemePreview(values: values)
      }
      if record?.canReset == true {
        RentivoWizardSection("Herança") {
          Button(resetRequested ? "Manter personalização" : "Restaurar herança", role: .destructive) {
            resetRequested.toggle()
          }
            .disabled(saving)
            .accessibilityIdentifier("theme.form.reset")
          if resetRequested {
            Label("Restauração selecionada", systemImage: "checkmark.circle.fill")
              .foregroundStyle(RentivoColors.emerald)
          }
        }
      }
    case .review:
      inheritanceSection
      RentivoWizardSection("Resumo do tema") {
        RentivoWizardReviewRow(label: "Fonte de títulos", value: values.headerFont.rawValue)
        RentivoWizardReviewRow(label: "Fonte de texto", value: values.textFont.rawValue)
        RentivoWizardReviewRow(label: "Cor primária", value: values.primary)
        RentivoWizardReviewRow(
          label: "Configuração",
          value: resetRequested
            ? "Restaurar herança"
            : (record?.stored == nil && !isDirty ? "Tema herdado" : "Personalização deste nível")
        )
      }
      if resetRequested {
        RentivoWizardSection("Alteração selecionada") {
          Label(
            "Restaurar herança removerá a personalização somente depois da confirmação final.",
            systemImage: "arrow.triangle.branch"
          )
          .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
    }
  }

  @ViewBuilder
  private var inheritanceSection: some View {
    if let record {
      RentivoWizardSection("Herança") {
        RentivoWizardReviewRow(label: "Responsável", value: record.ownerName)
        RentivoWizardReviewRow(label: "Origem efetiva", value: record.effectiveSource.label)
          .accessibilityIdentifier("theme.source")
        if record.stored == nil {
          Label(
            "Este nível herda o tema de \(record.effectiveSource.label.lowercased()).",
            systemImage: "arrow.triangle.branch"
          )
          .font(.footnote)
          .foregroundStyle(RentivoColors.secondaryInk)
        }
        if record.canEdit == false {
          Label("Seu acesso permite somente consultar este tema.", systemImage: "eye.fill")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
    } else {
      RentivoWizardSection("Carregando tema") {
        ProgressView()
      }
    }
  }

  private func commit() {
    guard validateAllColorsAndRoute() else { return }
    if resetRequested, record?.canReset == true {
      Task { await reset() }
    } else if record?.canEdit == true {
      Task { await save() }
    } else {
      dismiss()
    }
  }

  private func load() async {
    let requestDraftRevision = draftRevision
    let requestDraft = values
    readinessMessage = nil
    do {
      let loaded = try await app.dependencies.themes.theme(target: target)
      guard let loadedValuesToApply = ThemeWizardRules.loadedValuesToApply(
        loaded.stored ?? loaded.effective,
        requestDraft: requestDraft,
        currentDraft: values,
        requestDraftRevision: requestDraftRevision,
        currentDraftRevision: draftRevision
      ) else {
        readinessMessage = "O tema mudou durante o carregamento. Tente novamente para atualizar os dados."
        return
      }
      record = loaded
      values = loadedValuesToApply
      loadedValues = loadedValuesToApply
      themeLoaded = true
    } catch {
      self.error = DemoError(error)
      if record == nil { themeLoaded = false }
    }
  }

  private func validateCurrentStep() -> Bool {
    validationMessage = nil
    switch step {
    case .primaryColors:
      return validateColors([.primary, .primaryLight, .secondary])
    case .textAndContrast:
      return validateColors([.secondaryDark, .textColor, .textContrast])
    case .typography, .preview, .review:
      return true
    }
  }

  private func validateAllColorsAndRoute() -> Bool {
    let primaryFields: [ThemeWizardField] = [.primary, .primaryLight, .secondary]
    if let invalid = primaryFields.first(where: { ThemeWizardRules.colorValidationMessage(value(for: $0)) != nil }) {
      step = .primaryColors
      validationMessage = ThemeWizardRules.invalidColorMessage
      scheduleFocus(invalid)
      return false
    }
    let contrastFields: [ThemeWizardField] = [.secondaryDark, .textColor, .textContrast]
    if let invalid = contrastFields.first(where: { ThemeWizardRules.colorValidationMessage(value(for: $0)) != nil }) {
      step = .textAndContrast
      validationMessage = ThemeWizardRules.invalidColorMessage
      scheduleFocus(invalid)
      return false
    }
    return true
  }

  private func validateColors(_ fields: [ThemeWizardField]) -> Bool {
    guard let invalid = fields.first(where: { ThemeWizardRules.colorValidationMessage(value(for: $0)) != nil }) else {
      return true
    }
    validationMessage = ThemeWizardRules.invalidColorMessage
    scheduleFocus(invalid)
    return false
  }

  private func value(for field: ThemeWizardField) -> String {
    switch field {
    case .primary: values.primary
    case .primaryLight: values.primaryLight
    case .secondary: values.secondary
    case .secondaryDark: values.secondaryDark
    case .textColor: values.textColor
    case .textContrast: values.textContrast
    }
  }

  private func validationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("theme.form.validation")
  }

  private func save() async {
    guard !saving, record?.canEdit == true else { return }
    saving = true
    defer { saving = false }
    do {
      try await app.dependencies.themes.updateTheme(target: target, values: values)
      await load()
      app.showNotice("Tema atualizado.")
      dismiss()
    } catch { self.error = DemoError(error) }
  }

  private func reset() async {
    guard !saving, record?.canReset == true else { return }
    saving = true
    defer { saving = false }
    do {
      try await app.dependencies.themes.resetTheme(target: target)
      resetRequested = false
      await load()
      app.showNotice("Herança de tema restaurada.")
      dismiss()
    } catch { self.error = DemoError(error) }
  }

  private func scheduleFocus(_ field: ThemeWizardField) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
  }
}

private struct ThemeColorField: View {
  let title: String
  @Binding var value: String
  let field: ThemeWizardField
  let focusedField: FocusState<ThemeWizardField?>.Binding
  let accessibilityFocusedField: AccessibilityFocusState<ThemeWizardField?>.Binding

  var body: some View {
    HStack {
      Circle()
        .fill(Color(hex: value) ?? .clear)
        .frame(width: 24, height: 24)
        .overlay { Circle().stroke(RentivoColors.ink.opacity(0.4)) }
      TextField(title, text: $value)
        .textInputAutocapitalization(.characters)
        .font(.system(.body, design: .monospaced))
        .focused(focusedField, equals: field)
        .accessibilityFocused(accessibilityFocusedField, equals: field)
        .accessibilityIdentifier("theme.form.color.\(field.accessibilityIdentifier)")
    }
  }
}

private struct ThemePreview: View {
  let values: ThemeValues

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      Text("Fatura Rentivo")
        .font(.title2.bold())
        .foregroundStyle(Color(hex: values.textColor) ?? RentivoColors.ink)
      Text("Uma prévia local das cores do documento.")
        .foregroundStyle(Color(hex: values.textColor) ?? RentivoColors.ink)
      Text("R$ 2.450,00")
        .font(.system(.title3, design: .monospaced, weight: .bold))
        .foregroundStyle(Color(hex: values.textContrast) ?? .white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(hex: values.primary) ?? RentivoColors.emerald)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding()
    .background(Color(hex: values.primaryLight) ?? RentivoColors.emeraldLight)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}

extension ThemeSource {
  fileprivate var label: String {
    switch self {
    case .billing: "Cobrança"
    case .organization: "Organização"
    case .user: "Usuário"
    case .default: "Padrão Rentivo"
    }
  }
}

extension Color {
  init?(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}
