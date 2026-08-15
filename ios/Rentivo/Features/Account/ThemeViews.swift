import SwiftUI

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

  /// True once the user has changed a field since the last successful load/save.
  /// Guards against `.task(id:)` reloads (triggered by unrelated `app.dataRevision`
  /// bumps) silently overwriting in-progress, unsaved color edits.
  private var isDirty: Bool {
    values != (loadedValues ?? .rentivo)
  }

  var body: some View {
    RentivoFormWizard(
      title: "Aparência",
      descriptors: descriptors,
      selectedStep: $step,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: step == .review ? (record?.canEdit == true ? "Salvar" : "Concluir") : "Continuar",
      onValidateAndAdvance: { true },
      onCommit: commit
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || saving)
    .task(id: app.dataRevision) {
      guard !isDirty else { return }
      await load()
    }
    .alert(
      "Não foi possível atualizar",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK") { error = nil }
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
        Picker("Fonte de texto", selection: $values.textFont) {
          ForEach(ThemeFont.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
      }
    case .primaryColors:
      RentivoWizardSection(
        "Cores principais",
        subtitle: "Informe cores hexadecimais usadas nos destaques da marca."
      ) {
        ThemeColorField(title: "Primária", value: $values.primary)
        ThemeColorField(title: "Primária clara", value: $values.primaryLight)
        ThemeColorField(title: "Secundária", value: $values.secondary)
      }
    case .textAndContrast:
      RentivoWizardSection(
        "Texto e contraste",
        subtitle: "Ajuste superfícies escuras e a legibilidade do texto."
      ) {
        ThemeColorField(title: "Secundária escura", value: $values.secondaryDark)
        ThemeColorField(title: "Texto", value: $values.textColor)
        ThemeColorField(title: "Texto de contraste", value: $values.textContrast)
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
          Button("Restaurar herança", role: .destructive) { Task { await reset() } }
            .disabled(saving)
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
          value: record?.stored == nil && !isDirty ? "Tema herdado" : "Personalização deste nível"
        )
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
    if record?.canEdit == true {
      Task { await save() }
    } else {
      dismiss()
    }
  }

  private func load() async {
    do {
      let loaded = try await app.dependencies.themes.theme(target: target)
      record = loaded
      values = loaded.stored ?? loaded.effective
      loadedValues = values
    } catch { self.error = DemoError(error) }
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
      await load()
      app.showNotice("Herança de tema restaurada.")
    } catch { self.error = DemoError(error) }
  }
}

private struct ThemeColorField: View {
  let title: String
  @Binding var value: String

  var body: some View {
    HStack {
      Circle()
        .fill(Color(hex: value) ?? .clear)
        .frame(width: 24, height: 24)
        .overlay { Circle().stroke(RentivoColors.ink.opacity(0.4)) }
      TextField(title, text: $value)
        .textInputAutocapitalization(.characters)
        .font(.system(.body, design: .monospaced))
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
