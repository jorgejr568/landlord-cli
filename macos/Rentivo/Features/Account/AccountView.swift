import AppKit
import RentivoCore
import SwiftUI

struct AccountView: View {
  @Environment(AppModel.self) private var app
  @State private var showDeleteAccountAlert = false
  @State private var deleteAccountPassword = ""

  var body: some View {
    List {
      Section {
        HStack(spacing: RentivoSpacing.medium) {
          BrandMark(compact: true)
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(app.usesLiveAPI ? "Sua conta" : "Conta de demonstração").font(RentivoTypography.cardTitle)
            Text(app.currentUser.email)
              .font(RentivoTypography.body)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
        .padding(.vertical, RentivoSpacing.small)
      }

      RentivoSection("Perfil") {
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

      RentivoSection("Personalização e integrações") {
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
        RentivoSection("Demonstração") {
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

      RentivoSection("Sobre e suporte") {
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
              ProgressView().controlSize(.small)
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
        Text(title).font(RentivoTypography.cardTitle)
        Text(subtitle)
          .font(RentivoTypography.caption)
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
      RentivoSection("Conta") {
        LabeledContent("E-mail", value: app.currentUser.email)
        LabeledContent("Ambiente", value: app.usesLiveAPI ? "Rentivo" : "Demonstração local")
      }
      RentivoSection("PIX pessoal") {
        if hasLoaded {
          // The viewer lock sits on the fields rather than on the whole section, because the
          // section also holds the retry below. SwiftUI's `disabled` only accumulates — a
          // descendant cannot re-enable itself — so a lock at section level took the retry with
          // it, and a load that failed in viewer mode had no way back.
          Group {
            TextField("Chave PIX", text: $form.key)
            TextField("Nome do recebedor", text: $form.merchantName)
            TextField("Cidade", text: $form.merchantCity)
          }
          .disabled(isDemoViewerLocked)
        } else if let loadFailureMessage {
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            Label(loadFailureMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(RentivoColors.coral)
            // Re-reading the configuration is not editing it, so this stays live in viewer mode.
            Button("Tentar novamente") { Task { await load() } }
          }
          .accessibilityIdentifier("profile.pix.error")
        } else {
          HStack(spacing: RentivoSpacing.small) {
            ProgressView().controlSize(.small)
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
        .font(RentivoTypography.caption)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Dados e PIX")
    .toolbar {
      if !isDemoViewerLocked {
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await save() }
          } label: {
            if isSaving {
              ProgressView().controlSize(.small)
            } else {
              Text("Salvar")
            }
          }
          .disabled(!hasLoaded || isSaving || !form.isSavable)
          .accessibilityIdentifier("profile.pix.save")
        }
      }
    }
    .task { await load() }
  }

  /// The fields stay behind the load rather than starting empty: a blank form mid-request reads as
  /// an account with no PIX configured, and anything typed into it would be overwritten the moment
  /// the real values landed.
  private func load() async {
    loadFailureMessage = nil
    do {
      form = ProfilePIXForm(profile: try await app.loadProfile())
      hasLoaded = true
    } catch {
      // Reported in the section, with a retry, rather than through the global banner: the failure
      // is what the section is standing in for, so that is where it belongs.
      loadFailureMessage = DemoError(error).message
    }
  }

  private func save() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      form = ProfilePIXForm(profile: try await app.updateProfilePIX(form.configuration))
      app.showNotice("PIX pessoal atualizado.")
      // This screen is pushed rather than presented, so the global banner is visible here.
    } catch { app.reportFailure(error) }
  }
}

/// Copies a one-time value (a TOTP secret, an API key) to the system pasteboard and confirms it
/// in place. macOS has no share sheet for these, so the pasteboard is the whole affordance and
/// the confirmation has to be visible enough to trust — it stays for a couple of seconds and
/// then fades back to the idle label.
struct ClipboardCopyButton: View {
  let value: String
  var title = "Copiar"
  var confirmationTitle = "Copiado"
  @State private var hasCopied = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    Button {
      copy()
    } label: {
      Label(hasCopied ? confirmationTitle : title, systemImage: hasCopied ? "checkmark" : "doc.on.doc")
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.bordered)
    .tint(hasCopied ? RentivoColors.emerald : nil)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hasCopied)
    .onDisappear { resetTask?.cancel() }
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    hasCopied = true
    // A second tap restarts the window rather than letting the first one's timer clear the
    // confirmation early.
    resetTask?.cancel()
    resetTask = Task {
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      hasCopied = false
    }
  }
}

extension View {
  /// Settles sheet content into place instead of having it appear fully formed with the window.
  /// Used by the "reveal" sheets (recovery codes, TOTP secret, API key secret), whose whole job
  /// is to draw attention to a value shown exactly once.
  func rentivoSheetIntro() -> some View {
    modifier(SheetIntro())
  }
}

private struct SheetIntro: ViewModifier {
  @State private var hasAppeared = false

  func body(content: Content) -> some View {
    content
      .opacity(hasAppeared ? 1 : 0)
      .scaleEffect(hasAppeared ? 1 : 0.97)
      .onAppear {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { hasAppeared = true }
      }
  }
}
