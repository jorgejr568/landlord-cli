import SwiftUI

struct AccountView: View {
  @Environment(AppModel.self) private var app
  @State private var showDeleteAccountAlert = false
  @State private var deleteAccountPassword = ""
  @State private var showingProfilePIX = false
  @State private var showingTheme = false
  @State private var deletionReadiness: AccountDeletionReadiness?
  @State private var deletionReadinessError: String?
  @State private var loadingDeletionReadiness = false

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
        .disabled(
          app.isDeletingAccount || loadingDeletionReadiness
            || deletionReadiness?.canDelete == false
            || (app.usesLiveAPI && deletionReadiness == nil))
        if deletionReadiness?.reason == .soleOrganizationAdmin {
          Label(
            "Transfira a administração das organizações em que você é o único administrador antes de excluir a conta.",
            systemImage: "person.2.badge.gearshape"
          )
          .font(.footnote)
          .foregroundStyle(RentivoColors.coral)
        } else if deletionReadinessError != nil {
          Button("Verificar se a conta pode ser excluída") {
            Task { await loadDeletionReadiness() }
          }
          .font(.footnote)
        }
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
      .disabled(!BcryptPasswordRules.isAccepted(deleteAccountPassword))
    } message: {
      Text("Essa ação é permanente. Suas cobranças e seus dados pessoais serão excluídos.")
    }
    .task { await loadDeletionReadiness() }
  }

  private func loadDeletionReadiness() async {
    guard !loadingDeletionReadiness else { return }
    loadingDeletionReadiness = true
    deletionReadinessError = nil
    defer { loadingDeletionReadiness = false }
    do {
      deletionReadiness = try await app.dependencies.auth.accountDeletionReadiness()
    } catch {
      deletionReadinessError = DemoError(error).message
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
  @State private var profileLoaded = false
  @State private var profileLoadErrorMessage: String?
  @State private var draftRevision = 0
  @FocusState private var focusedField: Field?
  @AccessibilityFocusState private var accessibilityFocusedField: Field?

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
      isBusy: saving,
      isPrimaryEnabled: RentivoAsyncDraftLoadRules.isPrimaryEnabled(
        hasLoadedBaseline: profileLoaded
      ),
      finalActionTitle: finalActionTitle,
      onValidateAndAdvance: validateCurrentStep,
      onCommit: commit
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || saving)
    .task { await loadProfile() }
    .onChange(of: form) { draftRevision &+= 1 }
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

  private var finalActionTitle: String {
    guard profileLoaded else { return "Carregando perfil…" }
    if isDemoViewerLocked { return "Concluir" }
    return form.configuration == nil ? "Limpar PIX" : "Salvar PIX"
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
          .disabled(isDemoViewerLocked || !profileLoaded)
          .focused($focusedField, equals: .key)
          .accessibilityFocused($accessibilityFocusedField, equals: .key)
          .accessibilityIdentifier("profile.pix.key")
        if isDemoViewerLocked { readOnlyNotice }
        if let profileLoadErrorMessage {
          errorLabel(profileLoadErrorMessage)
          Button("Tentar novamente") { Task { await loadProfile() } }
            .accessibilityIdentifier("profile.pix.retry")
        }
      }
    case .recipient:
      RentivoWizardSection(
        "Dados do recebedor",
        subtitle: "Estes dados acompanham a chave nas cobranças pessoais."
      ) {
        TextField("Nome do recebedor", text: $form.merchantName)
          .disabled(isDemoViewerLocked || !profileLoaded)
          .focused($focusedField, equals: .merchantName)
          .accessibilityFocused($accessibilityFocusedField, equals: .merchantName)
          .accessibilityIdentifier("profile.pix.merchant-name")
        TextField("Cidade", text: $form.merchantCity)
          .textInputAutocapitalization(.characters)
          .disabled(isDemoViewerLocked || !profileLoaded)
          .focused($focusedField, equals: .city)
          .accessibilityFocused($accessibilityFocusedField, equals: .city)
          .accessibilityIdentifier("profile.pix.city")
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
      scheduleFocus(.key)
    } else if name.isEmpty || name.unicodeScalars.count > 25 {
      step = .recipient
      scheduleFocus(.merchantName)
    } else {
      step = .recipient
      scheduleFocus(.city)
    }
  }

  private var profilePIXValidationMessage: String {
    form.validationMessage ?? "Revise os dados do PIX."
  }

  private func commit() {
    if isDemoViewerLocked {
      dismiss()
    } else {
      Task { await save() }
    }
  }

  private func loadProfile() async {
    let requestDraft = form
    let requestRevision = draftRevision
    profileLoadErrorMessage = nil
    do {
      let loaded = ProfilePIXForm(profile: try await app.loadProfile())
      guard RentivoAsyncDraftLoadRules.shouldApply(
        requestDraft: requestDraft,
        currentDraft: form,
        requestRevision: requestRevision,
        currentRevision: draftRevision
      ) else {
        profileLoadErrorMessage = "O perfil mudou durante o carregamento. Tente novamente para atualizar os dados."
        return
      }
      form = loaded
      loadedForm = loaded
      profileLoaded = true
    } catch {
      profileLoadErrorMessage = DemoError(error).message
    }
  }

  private func scheduleFocus(_ field: Field) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
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
      app.showNotice(form.configuration == nil ? "PIX pessoal removido." : "PIX pessoal atualizado.")
      dismiss()
    } catch { submitErrorMessage = DemoError(error).message }
  }
}
