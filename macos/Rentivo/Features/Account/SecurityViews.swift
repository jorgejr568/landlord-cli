import AppKit
import RentivoCore
import SwiftUI

struct SecurityView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<SecuritySummary> = .idle
  @State private var recoveryCodes: [String] = []
  @State private var showingRecoveryCodes = false
  @State private var enrollment: TOTPEnrollment?
  @State private var showingDisableTOTP = false
  @State private var password = ""
  @State private var passkeyPendingDelete: Passkey?

  /// Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is
  /// connected to the live API, the signed-in user owns their own account and this
  /// screen should be fully enabled regardless of the demo viewer-mode toggle.
  private var isDemoViewerLocked: Bool {
    !app.usesLiveAPI && app.demoSettings.viewerMode
  }

  var body: some View {
    PageStateView(state: state) { summary in
      List {
        Section("Senha") {
          NavigationLink {
            ChangePasswordView()
          } label: {
            Label("Alterar senha", systemImage: "key.fill")
          }
        }
        Section("Autenticação em duas etapas") {
          LabeledContent("Aplicativo autenticador", value: summary.totpEnabled ? "Ativado" : "Desativado")
          if !isDemoViewerLocked {
            if summary.totpEnabled {
              Button("Desativar", role: .destructive) { showingDisableTOTP = true }
            } else {
              Button("Configurar aplicativo autenticador") { Task { await beginTOTP() } }
            }
            Button("Gerar novos códigos de recuperação") {
              Task { await regenerateCodes() }
            }
          }
          LabeledContent("Códigos disponíveis", value: "\(summary.recoveryCodeCount)")
        }
        Section("Chaves de acesso") {
          if summary.passkeys.isEmpty {
            Text("Nenhuma chave de acesso registrada ainda.")
              .font(.footnote)
              .foregroundStyle(RentivoColors.secondaryInk)
          } else {
            ForEach(summary.passkeys) { passkey in
              VStack(alignment: .leading, spacing: RentivoSpacing.small) {
                Text(passkey.name).font(.headline)
                Text("Último uso: \(passkey.lastUsedAt?.formattedPTBR(time: .shortened) ?? "nunca")")
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
                if !isDemoViewerLocked {
                  Button("Excluir", role: .destructive) { passkeyPendingDelete = passkey }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("security.passkey.delete")
                }
              }
            }
          }
          Text("Para registrar uma nova chave de acesso, entre pelo navegador do Rentivo. Ela ficará disponível automaticamente neste aplicativo.")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      .scrollContentBackground(.hidden)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Segurança")
    .task(id: app.dataRevision) { await load() }
    .sheet(isPresented: $showingRecoveryCodes) {
      RecoveryCodeView(codes: recoveryCodes)
    }
    .sheet(isPresented: Binding(presence: $enrollment)) {
      if let enrollment {
        TOTPEnrollmentView(enrollment: enrollment) { code in
          await confirmTOTP(code: code)
        }
      }
    }
    .alert("Desativar autenticação em duas etapas", isPresented: $showingDisableTOTP) {
      SecureField("Senha atual", text: $password)
      Button("Desativar", role: .destructive) { Task { await disableTOTP() } }
      Button("Cancelar", role: .cancel) { password = "" }
    } message: {
      Text("Confirme sua senha para desativar o aplicativo autenticador.")
    }
    .confirmationDialog(
      "Excluir esta chave de acesso?",
      isPresented: Binding(presence: $passkeyPendingDelete),
      presenting: passkeyPendingDelete
    ) { passkey in
      Button("Excluir chave de acesso", role: .destructive) {
        Task { await remove(passkey) }
      }
      .accessibilityIdentifier("security.passkey.delete.confirm")
      Button("Cancelar", role: .cancel) {}
        .accessibilityIdentifier("security.passkey.delete.cancel")
    } message: { passkey in
      Text("\"\(passkey.name)\" não poderá mais ser usada para entrar neste dispositivo. Esta ação não pode ser desfeita.")
    }
  }

  private func load() async {
    // Every MFA/passkey/password mutation below ends in `load()`, so this is also what keeps the
    // security summary on screen while one of them refreshes it.
    state.prepareForRefresh()
    do { state = .loaded(try await app.dependencies.security.securitySummary()) } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }

  private func beginTOTP() async {
    do {
      enrollment = try await app.dependencies.security.beginTOTPEnrollment()
    } catch { app.reportFailure(error) }
  }

  private func confirmTOTP(code: String) async {
    do {
      recoveryCodes = try await app.dependencies.security.confirmTOTPEnrollment(code: code)
      enrollment = nil
      await load()
      showingRecoveryCodes = true
    } catch { app.reportFailure(error) }
  }

  private func disableTOTP() async {
    do {
      try await app.dependencies.security.disableTOTP(password: password)
      password = ""
      await load()
    } catch { app.reportFailure(error) }
  }

  private func regenerateCodes() async {
    do {
      recoveryCodes = try await app.dependencies.security.regenerateRecoveryCodes()
      await load()
      showingRecoveryCodes = true
    } catch { app.reportFailure(error) }
  }

  private func remove(_ passkey: Passkey) async {
    do {
      try await app.dependencies.security.deletePasskey(id: passkey.id)
      await load()
    } catch { app.reportFailure(error) }
  }
}

private struct ChangePasswordView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var isSaving = false
  @State private var validationMessage: String?

  var body: some View {
    Form {
      Section {
        SecureField("Senha atual", text: $currentPassword)
          .textContentType(.password)
        SecureField("Nova senha", text: $newPassword)
          .textContentType(.newPassword)
        SecureField("Confirmar nova senha", text: $confirmPassword)
          .textContentType(.newPassword)
      } header: {
        Text("Alterar senha")
      } footer: {
        Text("Use uma senha forte e exclusiva para sua conta Rentivo.")
      }

      if let validationMessage {
        Section {
          Label(validationMessage, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(RentivoColors.coral)
        }
      }

      Section {
        Button("Salvar nova senha", action: save)
          .disabled(isSaving || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Senha")
  }

  private func save() {
    guard newPassword == confirmPassword else {
      validationMessage = "As senhas não coincidem."
      return
    }
    validationMessage = nil
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await app.dependencies.security.changePassword(
          currentPassword: currentPassword, newPassword: newPassword, confirmPassword: confirmPassword
        )
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        app.showNotice("Senha alterada com sucesso.")
        dismiss()
      } catch {
        validationMessage = DemoError(error).message
      }
    }
  }
}

private struct RecoveryCodeView: View {
  @Environment(\.dismiss) private var dismiss
  let codes: [String]

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        Label("Códigos de recuperação", systemImage: "shield.lefthalf.filled")
          .font(RentivoTypography.title)
        Text("Guarde estes códigos em local seguro. Eles aparecem uma única vez.")
          .foregroundStyle(RentivoColors.secondaryInk)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
          ForEach(codes, id: \.self) { code in
            Text(code)
              .font(.system(.body, design: .monospaced, weight: .bold))
              .textSelection(.enabled)
              .padding()
              .frame(maxWidth: .infinity)
              .background(RentivoColors.surface)
              .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }
        // Retyping ten codes by hand is exactly the kind of thing a Mac user expects to copy in
        // one go, so the whole set goes to the pasteboard one code per line.
        ClipboardCopyButton(value: codes.joined(separator: "\n"), title: "Copiar códigos")
        Spacer()
      }
      .rentivoSheetIntro()
      .padding(RentivoSpacing.page)
      .rentivoPage()
      .navigationTitle("Recuperação")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } }
      }
    }
    .rentivoSheetFrame()
  }
}

private struct TOTPEnrollmentView: View {
  @Environment(\.dismiss) private var dismiss
  let enrollment: TOTPEnrollment
  let onConfirm: (String) async -> Void
  @State private var code = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        Label("Configure seu autenticador", systemImage: "qrcode")
          .font(RentivoTypography.title)
        Text("Adicione esta chave manualmente ao seu aplicativo autenticador e informe o código de seis dígitos.")
        HStack(alignment: .top, spacing: RentivoSpacing.large) {
          // The Mac has no camera pointed at itself, so the QR code is here to be scanned by the
          // phone that holds the authenticator app; the secret beside it stays for manual entry.
          if let qrCode = enrollment.qrCodeImage {
            VStack(spacing: RentivoSpacing.small) {
              Image(nsImage: qrCode)
                .interpolation(.none)
                .resizable()
                .frame(width: 160, height: 160)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                  RoundedRectangle(cornerRadius: 12).stroke(RentivoColors.ink, lineWidth: 2)
                }
                .accessibilityLabel("QR Code do autenticador")
              Text("Ou escaneie com seu telefone.")
                .font(.footnote)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
          }
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            Text(enrollment.secret)
              .font(.system(.body, design: .monospaced, weight: .bold))
              .textSelection(.enabled)
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RentivoColors.surface)
              .clipShape(RoundedRectangle(cornerRadius: 12))
            ClipboardCopyButton(value: enrollment.secret, title: "Copiar chave")
          }
        }
        TextField("Código do autenticador", text: $code)
          .textContentType(.oneTimeCode)
        Button("Confirmar") { Task { await onConfirm(code) } }
          .buttonStyle(RentivoButtonStyle())
          .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Spacer()
      }
      .rentivoSheetIntro()
      .padding(RentivoSpacing.page)
      .rentivoPage()
      .navigationTitle("Autenticador")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
      }
    }
    .rentivoSheetFrame()
  }
}

extension TOTPEnrollment {
  /// The enrollment QR code as an image, or `nil` when the payload isn't decodable base64 PNG
  /// data — in which case the sheet falls back to the manually-entered secret alone.
  fileprivate var qrCodeImage: NSImage? {
    guard let data = Data(base64Encoded: qrCodeBase64) else { return nil }
    return NSImage(data: data)
  }
}
