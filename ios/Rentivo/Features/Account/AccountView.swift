import SwiftUI

struct AccountView: View {
  @Environment(AppModel.self) private var app
  @State private var showDeleteAccountAlert = false
  @State private var deleteAccountPassword = ""
  @State private var showingProfilePIX = false
  @State private var showingTheme = false

  var body: some View {
    List {
      Section {
        HStack(spacing: RentivoSpacing.medium) {
          BrandMark(compact: true)
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(app.usesLiveAPI ? "Sua conta" : "Conta de demonstração").font(.headline)
            Text(app.currentUser.email)
              .font(.subheadline)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
        .padding(.vertical, RentivoSpacing.small)
      }

      Section("Perfil") {
        Button {
          showingProfilePIX = true
        } label: {
          AccountRow(title: "Dados e PIX", subtitle: "Chave e dados do recebedor", symbol: "qrcode")
        }
        .accessibilityIdentifier("account.pix")
        NavigationLink {
          SecurityView()
        } label: {
          AccountRow(
            title: "Segurança", subtitle: "Senha, TOTP e chaves de acesso",
            symbol: "lock.shield.fill")
        }
      }

      Section("Personalização e integrações") {
        NavigationLink {
          APIKeyListView()
        } label: {
          AccountRow(
            title: "Chaves de integração", subtitle: "Escopos e acessos", symbol: "key.fill")
        }
        Button {
          showingTheme = true
        } label: {
          AccountRow(
            title: "Aparência", subtitle: "Fontes, cores e prévia", symbol: "paintpalette.fill")
        }
        .accessibilityIdentifier("account.theme")
      }

      if !app.usesLiveAPI {
        Section("Demonstração") {
          NavigationLink {
            DemoScenariosView()
          } label: {
            AccountRow(
              title: "Cenários do app",
              subtitle: "Atraso, falha, vazio e permissões",
              symbol: "slider.horizontal.3"
            )
          }
          .accessibilityIdentifier("account.demo")
        }
      }

      Section("Sobre e suporte") {
        Link(destination: LiveAPIClient.productionURL.appending(path: "support")) {
          AccountRow(
            title: "Suporte",
            subtitle: "Fale com a gente",
            symbol: "questionmark.circle.fill"
          )
        }
        Link(destination: LiveAPIClient.productionURL.appending(path: "privacy")) {
          AccountRow(
            title: "Política de privacidade",
            subtitle: "Como tratamos seus dados",
            symbol: "hand.raised.fill"
          )
        }
        Link(destination: LiveAPIClient.productionURL.appending(path: "terms")) {
          AccountRow(
            title: "Termos de uso",
            subtitle: "Regras do serviço",
            symbol: "doc.text.fill"
          )
        }
      }

      Section {
        Button(role: .destructive) {
          Task { await app.signOut() }
        } label: {
          if app.isSigningOut {
            HStack {
              ProgressView()
              Text("Saindo...")
            }
            .frame(maxWidth: .infinity)
          } else {
            Label("Sair", systemImage: "rectangle.portrait.and.arrow.right")
              .frame(maxWidth: .infinity)
          }
        }
        .disabled(app.isSigningOut)

        Button(role: .destructive) { showDeleteAccountAlert = true } label: {
          Label("Excluir conta", systemImage: "trash.fill").frame(maxWidth: .infinity)
        }
        .disabled(app.isDeletingAccount)
      }
    }
    .scrollContentBackground(.hidden)
    .background(RentivoColors.paper)
    .navigationTitle("Conta")
    .rentivoFullScreenWizard(isPresented: $showingProfilePIX) {
      ProfilePixView()
    }
    .rentivoFullScreenWizard(isPresented: $showingTheme) {
      ThemeEditorView(target: .user)
    }
    .alert("Excluir sua conta?", isPresented: $showDeleteAccountAlert) {
      SecureField("Senha", text: $deleteAccountPassword)
      Button("Cancelar", role: .cancel) { deleteAccountPassword = "" }
      Button("Excluir conta", role: .destructive) {
        let password = deleteAccountPassword
        deleteAccountPassword = ""
        Task { await app.deleteAccount(password: password) }
      }
    } message: {
      Text("Essa ação é permanente. Suas cobranças e seus dados pessoais serão excluídos.")
    }
  }
}

private struct AccountRow: View {
  let title: String
  let subtitle: String
  let symbol: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
        Text(title).font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    } icon: {
      Image(systemName: symbol).foregroundStyle(RentivoColors.emerald)
    }
  }
}

struct ProfilePixView: View {
  private enum Step: CaseIterable {
    case key
    case recipient
    case review
  }

  private enum Field: Hashable {
    case key
    case merchantName
    case city
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var form = ProfilePIXForm()
  @State private var loadedForm: ProfilePIXForm?
  @State private var step: Step = .key
  @State private var validationMessage: String?
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @FocusState private var focusedField: Field?

  /// Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is
  /// connected to the live API, the signed-in user owns their own account and this
  /// screen should be fully enabled regardless of the demo viewer-mode toggle.
  private var isDemoViewerLocked: Bool {
    !app.usesLiveAPI && app.demoSettings.viewerMode
  }

  var body: some View {
    RentivoFormWizard(
      title: "Dados e PIX",
      descriptors: descriptors,
      selectedStep: $step,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: primaryTitle,
      onValidateAndAdvance: validateCurrentStep,
      onCommit: commit
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || saving)
    .task {
      guard !isDirty else { return }
      do {
        let loaded = ProfilePIXForm(profile: try await app.loadProfile())
        form = loaded
        loadedForm = loaded
      } catch {
        submitErrorMessage = DemoError(error).message
      }
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .key, title: "Chave"),
      .init(id: .recipient, title: "Recebedor"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var isDirty: Bool {
    form != (loadedForm ?? ProfilePIXForm())
  }

  private var primaryTitle: String {
    guard step == .review else { return "Continuar" }
    if isDemoViewerLocked { return "Concluir" }
    return form.configuration.isEmpty ? "Limpar" : "Salvar"
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .key:
      RentivoWizardSection(
        "Chave PIX pessoal",
        subtitle: "Deixe a chave e os dados do recebedor vazios para remover a configuração atual."
      ) {
        TextField("Chave PIX", text: $form.key)
          .textInputAutocapitalization(.never)
          .disabled(isDemoViewerLocked)
          .focused($focusedField, equals: .key)
        if isDemoViewerLocked { readOnlyNotice }
      }
    case .recipient:
      RentivoWizardSection(
        "Dados do recebedor",
        subtitle: "Estes dados acompanham a chave nas cobranças pessoais."
      ) {
        TextField("Nome do recebedor", text: $form.merchantName)
          .disabled(isDemoViewerLocked)
          .focused($focusedField, equals: .merchantName)
        TextField("Cidade", text: $form.merchantCity)
          .textInputAutocapitalization(.characters)
          .disabled(isDemoViewerLocked)
          .focused($focusedField, equals: .city)
        if let validationMessage { errorLabel(validationMessage) }
      }
      RentivoWizardSection("Herança") {
        Label(
          "Cobranças pessoais sem PIX próprio herdam esta configuração.",
          systemImage: "arrow.triangle.branch"
        )
        .font(.footnote)
      }
    case .review:
      RentivoWizardSection("Conta") {
        RentivoWizardReviewRow(label: "E-mail", value: app.currentUser.email)
        RentivoWizardReviewRow(
          label: "Ambiente", value: app.usesLiveAPI ? "Rentivo" : "Demonstração local"
        )
      }
      RentivoWizardSection("PIX pessoal") {
        RentivoWizardReviewRow(label: "Chave", value: maskedKey)
        RentivoWizardReviewRow(
          label: "Recebedor",
          value: form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Não informado"
            : form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        RentivoWizardReviewRow(
          label: "Cidade",
          value: form.merchantCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Não informada"
            : form.merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      }
      if let submitErrorMessage {
        RentivoWizardSection("Não foi possível atualizar") {
          errorLabel(submitErrorMessage)
        }
      }
    }
  }

  private var readOnlyNotice: some View {
    Label("A configuração está disponível somente para consulta no modo visualizador.", systemImage: "eye.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.secondaryInk)
  }

  private var maskedKey: String {
    let key = form.key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return "Sem chave configurada" }
    guard key.count > 4 else { return key }
    return "••••\(key.suffix(4))"
  }

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("profile.pix.error")
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    guard step == .recipient else { return true }
    guard form.isSavable else {
      validationMessage = profilePIXValidationMessage
      routeToFirstInvalidField()
      return false
    }
    validationMessage = nil
    return true
  }

  private func routeToFirstInvalidField() {
    let key = form.key.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty {
      step = .key
      focusedField = .key
    } else if name.isEmpty || name.unicodeScalars.count > 25 {
      step = .recipient
      focusedField = .merchantName
    } else {
      step = .recipient
      focusedField = .city
    }
  }

  private var profilePIXValidationMessage: String {
    let configuration = form.configuration
    if !configuration.isEmpty && !configuration.isComplete {
      return "Preencha a chave, o nome e a cidade do recebedor, ou deixe todos os campos vazios."
    }
    if form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 25 {
      return "O nome do recebedor deve ter até 25 caracteres."
    }
    return "A cidade do recebedor deve ter até 15 caracteres."
  }

  private func commit() {
    if isDemoViewerLocked {
      dismiss()
    } else {
      Task { await save() }
    }
  }

  private func save() async {
    guard !saving else { return }
    guard form.isSavable else {
      validationMessage = profilePIXValidationMessage
      routeToFirstInvalidField()
      return
    }
    submitErrorMessage = nil
    saving = true
    defer { saving = false }
    do {
      form = ProfilePIXForm(profile: try await app.updateProfilePIX(form.configuration))
      loadedForm = form
      app.showNotice("PIX pessoal atualizado.")
      dismiss()
    } catch { submitErrorMessage = DemoError(error).message }
  }
}
