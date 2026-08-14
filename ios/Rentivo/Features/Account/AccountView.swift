import SwiftUI

struct AccountView: View {
  @Environment(AppModel.self) private var app
  @State private var showDeleteAccountAlert = false
  @State private var deleteAccountPassword = ""
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
        NavigationLink {
          ProfilePixView()
        } label: {
          AccountRow(title: "Dados e PIX", subtitle: "Chave e dados do recebedor", symbol: "qrcode")
        }
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
        NavigationLink {
          ThemeEditorView(target: .user)
        } label: {
          AccountRow(
            title: "Aparência", subtitle: "Fontes, cores e prévia", symbol: "paintpalette.fill")
        }
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
  @Environment(AppModel.self) private var app
  @State private var form = ProfilePIXForm()
  @State private var hasLoaded = false
  @State private var loadFailureMessage: String?
  @State private var isSaving = false

  /// Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is
  /// connected to the live API, the signed-in user owns their own account and this
  /// screen should be fully enabled regardless of the demo viewer-mode toggle.
  private var isDemoViewerLocked: Bool {
    !app.usesLiveAPI && app.demoSettings.viewerMode
  }

  var body: some View {
    Form {
      Section("Conta") {
        LabeledContent("E-mail", value: app.currentUser.email)
        LabeledContent("Ambiente", value: app.usesLiveAPI ? "Rentivo" : "Demonstração local")
      }
      Section("PIX pessoal") {
        if hasLoaded {
          Group {
            TextField("Chave PIX", text: $form.key)
              .textInputAutocapitalization(.never)
            TextField("Nome do recebedor", text: $form.merchantName)
            TextField("Cidade", text: $form.merchantCity)
              .textInputAutocapitalization(.characters)
            if let message = form.validationMessage {
              Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(RentivoColors.coral)
            }
          }
          .disabled(isDemoViewerLocked)
        } else if let loadFailureMessage {
          Label(loadFailureMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(RentivoColors.coral)
          Button("Tentar novamente") { Task { await load() } }
        } else {
          HStack {
            ProgressView()
            Text("Carregando seus dados…")
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
      }
      Section {
        Label(
          "Cobranças pessoais sem PIX próprio herdam esta configuração.",
          systemImage: "arrow.triangle.branch"
        )
        .font(.footnote)
      }
    }
    .navigationTitle("Dados e PIX")
    .toolbar {
      if !isDemoViewerLocked {
        Button {
          Task { await save() }
        } label: {
          if isSaving { ProgressView() } else { Text("Salvar") }
        }
          .disabled(!hasLoaded || isSaving || form.validationMessage != nil)
          .accessibilityIdentifier("profile.pix.save")
      }
    }
    .task { await load() }
  }

  private func load() async {
    loadFailureMessage = nil
    do {
      form = ProfilePIXForm(profile: try await app.loadProfile())
      hasLoaded = true
    } catch {
      loadFailureMessage = DemoError(error).message
    }
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      form = ProfilePIXForm(profile: try await app.updateProfilePIX(form.configuration))
      app.showNotice(form.configuration == nil ? "PIX pessoal removido." : "PIX pessoal atualizado.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}
