import SwiftUI
import UIKit

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
    @Bindable var app = app
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
        .accessibilityIdentifier("account.security")
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
    .rentivoTabContent()
    .scrollContentBackground(.hidden)
    .background(RentivoColors.paper)
    .navigationTitle("Conta")
    .navigationDestination(isPresented: $app.securityNavigationRequested) {
      SecurityView()
    }
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
    .noticeArea(.account)
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
  @State private var keyValidationMessage: String?
  @State private var merchantNameValidationMessage: String?
  @State private var cityValidationMessage: String?
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var profileLoaded = false
  @State private var profileLoadErrorMessage: String?
  @State private var draftRevision = 0
  @State private var isKeyRevealed = false
  @State private var pendingKeyType: PixKeyType?
  @State private var confirmingKeyTypeChange = false
  @State private var confirmingRemoval = false
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
    .onChange(of: step) { _, _ in isKeyRevealed = false }
    .confirmationDialog(
      "Alterar tipo de chave?",
      isPresented: $confirmingKeyTypeChange,
      titleVisibility: .visible
    ) {
      Button("Alterar e apagar", role: .destructive) { applyPendingKeyType() }
      Button("Cancelar", role: .cancel) { pendingKeyType = nil }
    } message: {
      Text("A chave digitada será apagada para evitar que seja interpretada no formato errado.")
    }
    .confirmationDialog(
      "Remover chave PIX?",
      isPresented: $confirmingRemoval,
      titleVisibility: .visible
    ) {
      Button("Remover chave", role: .destructive) { Task { await removePix() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("As cobranças pessoais que herdam esta configuração ficarão sem PIX até que outra chave seja cadastrada.")
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

  private var finalActionTitle: String {
    guard profileLoaded else { return "Carregando perfil…" }
    if isDemoViewerLocked { return "Concluir" }
    return "Salvar PIX"
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .key:
      RentivoWizardSection(
        "Chave PIX pessoal",
        subtitle: "Escolha o tipo e informe a chave usada para receber pagamentos."
      ) {
        RentivoFormField(
          label: "Tipo de chave",
          state: isDemoViewerLocked || !profileLoaded ? .disabled : .normal
        ) {
          Picker("", selection: keyTypeBinding) {
            ForEach(PixKeyType.allCases, id: \.self) { type in
              Text(type.label).tag(type)
            }
          }
          .labelsHidden()
          .accessibilityLabel("Tipo de chave")
          .accessibilityIdentifier("profile.pix.key-type")
        }
        .disabled(isDemoViewerLocked || !profileLoaded)
        RentivoTextFormField(
          label: "Chave PIX",
          text: keyBinding,
          hint: form.keyType.hint,
          errorMessage: keyValidationMessage,
          isFocused: focusBinding(.key),
          isAccessibilityFocused: accessibilityFocusBinding(.key),
          accessibilityIdentifier: "profile.pix.key"
        )
          .keyboardType(pixKeyboardType)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .disabled(isDemoViewerLocked || !profileLoaded)
        if let submitErrorMessage {
          errorLabel(submitErrorMessage)
            .accessibilityIdentifier("profile.pix.error")
        }
        if isDemoViewerLocked { readOnlyNotice }
        if let profileLoadErrorMessage {
          errorLabel(profileLoadErrorMessage)
          Button("Tentar novamente") { Task { await loadProfile() } }
            .accessibilityIdentifier("profile.pix.retry")
        }
      }
      if hasPersistedPix, !isDemoViewerLocked, profileLoaded, !saving {
        Button("Remover chave", role: .destructive) { confirmingRemoval = true }
          .buttonStyle(.bordered)
          .frame(minHeight: 44)
          .accessibilityIdentifier("profile.pix.remove")
      }
    case .recipient:
      RentivoWizardSection(
        "Dados do recebedor",
        subtitle: "Estes dados acompanham a chave nas cobranças pessoais."
      ) {
        RentivoTextFormField(
          label: "Nome do recebedor",
          text: $form.merchantName,
          errorMessage: merchantNameValidationMessage,
          isFocused: focusBinding(.merchantName),
          isAccessibilityFocused: accessibilityFocusBinding(.merchantName),
          accessibilityIdentifier: "profile.pix.merchant-name"
        )
          .disabled(isDemoViewerLocked || !profileLoaded)
          .onChange(of: form.merchantName) {
            if merchantNameValidationMessage != nil { validateRecipientFields() }
          }
        RentivoTextFormField(
          label: "Cidade",
          text: $form.merchantCity,
          errorMessage: cityValidationMessage,
          isFocused: focusBinding(.city),
          isAccessibilityFocused: accessibilityFocusBinding(.city),
          accessibilityIdentifier: "profile.pix.city"
        )
          .disabled(isDemoViewerLocked || !profileLoaded)
          .onChange(of: form.merchantCity) {
            if cityValidationMessage != nil { validateRecipientFields() }
          }
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
      }
      RentivoWizardSection("PIX pessoal") {
        RentivoPixKeyReview(
          input: pixKeyInput,
          isRevealed: $isKeyRevealed,
          accessibilityIdentifier: "profile.pix.review.reveal"
        )
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

  private var pixKeyInput: PixKeyInput {
    PixKeyInput(
      type: form.keyType,
      value: form.key,
      preservesUnclassifiedLegacyValue: form.preservesUnclassifiedLegacyKey
    )
  }

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("profile.pix.error")
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    if isDemoViewerLocked { return true }
    switch step {
    case .key:
      keyValidationMessage = pixKeyInput.validationMessage
      if keyValidationMessage != nil { scheduleFocus(.key) }
      return keyValidationMessage == nil
    case .recipient:
      validateRecipientFields()
      if merchantNameValidationMessage != nil { scheduleFocus(.merchantName); return false }
      if cityValidationMessage != nil { scheduleFocus(.city); return false }
      return true
    case .review:
      return true
    }
  }

  private func routeToFirstInvalidField() {
    let name = form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if pixKeyInput.validationMessage != nil {
      step = .key
      scheduleFocus(.key)
    } else if name.isEmpty || name.unicodeScalars.count > 255 {
      step = .recipient
      scheduleFocus(.merchantName)
    } else {
      step = .recipient
      scheduleFocus(.city)
    }
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
      keyValidationMessage = pixKeyInput.validationMessage
      validateRecipientFields()
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

  private var hasPersistedPix: Bool {
    !(loadedForm?.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  private var keyBinding: Binding<String> {
    Binding(
      get: { form.key },
      set: {
        form.key = PixKeyInput.formatted($0, as: form.keyType)
        form.preservesUnclassifiedLegacyKey = false
        if keyValidationMessage != nil { keyValidationMessage = pixKeyInput.validationMessage }
      }
    )
  }

  private var keyTypeBinding: Binding<PixKeyType> {
    Binding(
      get: { form.keyType },
      set: { newType in
        guard newType != form.keyType else { return }
        if pixKeyInput.requiresConfirmation(to: newType) {
          pendingKeyType = newType
          confirmingKeyTypeChange = true
        } else {
          form.keyType = newType
          form.preservesUnclassifiedLegacyKey = false
        }
      }
    )
  }

  private var pixKeyboardType: UIKeyboardType {
    switch form.keyType {
    case .cpf, .cnpj: .numberPad
    case .email: .emailAddress
    case .phone: .phonePad
    case .random: .asciiCapable
    }
  }

  private func applyPendingKeyType() {
    guard let pendingKeyType else { return }
    form.keyType = pendingKeyType
    form.key = ""
    form.preservesUnclassifiedLegacyKey = false
    self.pendingKeyType = nil
    scheduleFocus(.key)
  }

  private func validateRecipientFields() {
    let name = form.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let city = form.merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    merchantNameValidationMessage = name.isEmpty
      ? "Informe o nome do recebedor."
      : (name.unicodeScalars.count > 255
        ? "O nome do recebedor deve ter até 255 caracteres." : nil)
    cityValidationMessage = city.isEmpty
      ? "Informe a cidade do recebedor."
      : (city.unicodeScalars.count > 255
        ? "A cidade do recebedor deve ter até 255 caracteres." : nil)
  }

  private func removePix() async {
    guard !saving, hasPersistedPix else { return }
    submitErrorMessage = nil
    saving = true
    defer { saving = false }
    do {
      form = ProfilePIXForm(profile: try await app.updateProfilePIX(nil))
      loadedForm = form
      app.showNotice("PIX pessoal removido.")
      dismiss()
    } catch { submitErrorMessage = DemoError(error).message }
  }

  private func focusBinding(_ field: Field) -> Binding<Bool> {
    Binding(
      get: { focusedField == field },
      set: { focusedField = $0 ? field : (focusedField == field ? nil : focusedField) }
    )
  }

  private func accessibilityFocusBinding(_ field: Field) -> Binding<Bool> {
    Binding(
      get: { accessibilityFocusedField == field },
      set: {
        accessibilityFocusedField = $0
          ? field : (accessibilityFocusedField == field ? nil : accessibilityFocusedField)
      }
    )
  }
}
