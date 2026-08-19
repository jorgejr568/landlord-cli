import SwiftUI
import UIKit

enum SecurityViewRules {
  /// The one problem `code` a user pending MFA enrollment can still resolve from this screen: the
  /// backend answers every OTHER `GET /api/v1/security` read with the same `mfa_setup_required` 403
  /// while still allowing the TOTP *registration* routes (`totp/setup`, `totp/confirm`). Without
  /// recognizing this exact code, the summary read's 403 reads as a generic failure and strands the
  /// user on a dead end that tells them to do the one thing the screen won't let them do.
  static let mfaSetupRequiredCode = "mfa_setup_required"

  static func isMFASetupRequiredFailure(problemCode: String?) -> Bool {
    problemCode == mfaSetupRequiredCode
  }
}

struct SecurityView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<SecuritySummary> = .idle
  @State private var recoveryCodes: [String] = []
  @State private var isRegeneratingCodes = false
  @State private var showingRecoveryCodes = false
  @State private var enrollment: TOTPEnrollment?
  @State private var showingDisableTOTP = false
  @State private var showingChangePassword = false
  @State private var password = ""
  @State private var passkeyPendingDelete: Passkey?
  /// Set instead of `state = .failed(...)` when the summary read fails specifically with
  /// `mfa_setup_required`: that failure has a real next step (enroll TOTP), unlike every other
  /// failure `PageStateView`'s generic retry screen handles.
  @State private var mfaSetupRequired = false

  /// Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is
  /// connected to the live API, the signed-in user owns their own account and this
  /// screen should be fully enabled regardless of the demo viewer-mode toggle.
  private var isDemoViewerLocked: Bool {
    !app.usesLiveAPI && app.demoSettings.viewerMode
  }

  var body: some View {
    Group {
      if mfaSetupRequired {
        MFASetupOnlyView(
          enrollment: $enrollment,
          beginTOTP: { await beginTOTP() },
          confirmTOTP: { code in await confirmTOTP(code: code) }
        )
      } else {
        PageStateView(state: state) { summary in
          List {
            if summary.setupRequired {
              Section {
                Label(
                  "Sua organização exige autenticação multifator. Configure o aplicativo autenticador ou uma chave de acesso para continuar.",
                  systemImage: "exclamationmark.shield.fill"
                )
                .foregroundStyle(RentivoColors.coral)
                .accessibilityIdentifier("security.mfa.required")
              }
            }
            Section("Senha") {
              Button {
                showingChangePassword = true
              } label: {
                Label("Alterar senha", systemImage: "key.fill")
              }
              .accessibilityIdentifier("security.password.change")
            }
            Section("Autenticação em duas etapas") {
              LabeledContent("Aplicativo autenticador", value: summary.totpEnabled ? "Ativado" : "Desativado")
              if !isDemoViewerLocked {
                if summary.totpEnabled {
                  Button("Desativar", role: .destructive) { showingDisableTOTP = true }
                  Button {
                    Task { await regenerateCodes() }
                  } label: {
                    if isRegeneratingCodes {
                      HStack(spacing: RentivoSpacing.small) {
                        ProgressView().controlSize(.small)
                        Text("Gerando…")
                      }
                    } else {
                      Text("Gerar novos códigos de recuperação")
                    }
                  }
                  .disabled(isRegeneratingCodes)
                } else {
                  Button("Configurar aplicativo autenticador") { Task { await beginTOTP() } }
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
              if summary.organizationEnforced {
                Text("Sua organização exige que ao menos um fator de autenticação permaneça ativo.")
                  .font(.footnote)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
            }
          }
          .rentivoTabContent()
          .scrollContentBackground(.hidden)
        } retry: {
          await load()
        }
      }
    }
    .background(RentivoColors.paper)
    .navigationTitle("Segurança")
    .task(id: app.dataRevision) { await load() }
    .rentivoFullScreenWizard(isPresented: $showingChangePassword) {
      ChangePasswordView()
    }
    .sheet(isPresented: $showingRecoveryCodes) {
      RecoveryCodeView(codes: recoveryCodes)
    }
    .sheet(isPresented: Binding(get: { enrollment != nil }, set: { if !$0 { enrollment = nil } })) {
      if let enrollment {
        TOTPEnrollmentView(enrollment: enrollment) { code in
          await confirmTOTP(code: code)
        }
      }
    }
    .alert("Desativar autenticação em duas etapas", isPresented: $showingDisableTOTP) {
      SecureField("Senha atual", text: $password)
      Button("Desativar", role: .destructive) { Task { await disableTOTP() } }
        .disabled(!BcryptPasswordRules.isAccepted(password))
      Button("Cancelar", role: .cancel) { password = "" }
    } message: {
      Text("Confirme sua senha para desativar o aplicativo autenticador.")
    }
    .confirmationDialog(
      "Excluir esta chave de acesso?",
      isPresented: Binding(
        get: { passkeyPendingDelete != nil },
        set: { if !$0 { passkeyPendingDelete = nil } }
      ),
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
    .noticeArea(.security)
  }

  private func load() async {
    state = .loading
    mfaSetupRequired = false
    do {
      state = .loaded(try await app.dependencies.security.securitySummary())
    } catch {
      if SecurityViewRules.isMFASetupRequiredFailure(problemCode: (error as? LiveAPIError)?.problemCode) {
        mfaSetupRequired = true
      } else {
        state = .failed(DemoError(error))
      }
    }
  }

  private func beginTOTP() async {
    do {
      enrollment = try await app.dependencies.security.beginTOTPEnrollment()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  /// Returns the failure message instead of routing it to the global notice banner: the
  /// enrollment sheet stays open on a wrong code, and the banner renders behind it, so a rejected
  /// code would look like the button did nothing. `TOTPEnrollmentView` shows the result inline.
  private func confirmTOTP(code: String) async -> String? {
    do {
      recoveryCodes = try await app.dependencies.security.confirmTOTPEnrollment(code: code)
      enrollment = nil
      await load()
      showingRecoveryCodes = true
      return nil
    } catch { return DemoError(error).message }
  }

  private func disableTOTP() async {
    do {
      try await app.dependencies.security.disableTOTP(password: password)
      password = ""
      await load()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func regenerateCodes() async {
    guard !isRegeneratingCodes else { return }
    isRegeneratingCodes = true
    defer { isRegeneratingCodes = false }
    do {
      recoveryCodes = try await app.dependencies.security.regenerateRecoveryCodes()
      await load()
      showingRecoveryCodes = true
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func remove(_ passkey: Passkey) async {
    do {
      try await app.dependencies.security.deletePasskey(id: passkey.id)
      await load()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}

/// Shown instead of the normal Segurança screen when the summary read fails with
/// `mfa_setup_required`: every other read this screen would need (passkeys, change-password) is
/// blocked by the same policy, so the only way forward is finishing TOTP enrollment. Passkey
/// *registration* is web-only in this app already (see the footnote in the normal screen), so TOTP
/// is the one setup path reachable from here.
private struct MFASetupOnlyView: View {
  @Binding var enrollment: TOTPEnrollment?
  let beginTOTP: () async -> Void
  let confirmTOTP: (String) async -> String?

  var body: some View {
    ContentUnavailableView {
      Label("Configuração obrigatória", systemImage: "exclamationmark.shield.fill")
    } description: {
      Text(
        "Sua organização exige autenticação em duas etapas. Configure o aplicativo autenticador para continuar usando o Rentivo."
      )
    } actions: {
      Button("Configurar aplicativo autenticador") { Task { await beginTOTP() } }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("security.mfa.setup-required.configure")
    }
    .accessibilityIdentifier("security.mfa.setup-required")
    .sheet(isPresented: Binding(get: { enrollment != nil }, set: { if !$0 { enrollment = nil } })) {
      if let enrollment {
        TOTPEnrollmentView(enrollment: enrollment) { code in
          await confirmTOTP(code)
        }
      }
    }
  }
}

private struct ChangePasswordView: View {
  private enum Step: CaseIterable {
    case current
    case new
    case review
  }

  private enum Field: Hashable {
    case current
    case new
    case confirmation
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var isSaving = false
  @State private var validationMessage: String?
  @State private var step: Step = .current
  @FocusState private var focusedField: Field?
  @AccessibilityFocusState private var accessibilityFocusedField: Field?

  var body: some View {
    RentivoFormWizard(
      title: "Alterar senha",
      descriptors: descriptors,
      selectedStep: $step,
      isBusy: isSaving,
      finalActionTitle: "Alterar senha",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: save
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(isDirty || isSaving)
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .current, title: "Senha atual"),
      .init(id: .new, title: "Nova senha"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  private var isDirty: Bool {
    !currentPassword.isEmpty || !newPassword.isEmpty || !confirmPassword.isEmpty
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .current:
      RentivoWizardSection(
        "Confirme sua identidade",
        subtitle: "Informe a senha usada atualmente na sua conta."
      ) {
        SecureField("Senha atual", text: $currentPassword)
          .textContentType(.password)
          .focused($focusedField, equals: .current)
          .accessibilityFocused($accessibilityFocusedField, equals: .current)
          .accessibilityIdentifier("password.form.current")
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .new:
      RentivoWizardSection(
        "Escolha a nova senha",
        subtitle: "Use uma senha forte e exclusiva para sua conta Rentivo."
      ) {
        SecureField("Nova senha", text: $newPassword)
          .textContentType(.newPassword)
          .focused($focusedField, equals: .new)
          .accessibilityFocused($accessibilityFocusedField, equals: .new)
          .accessibilityIdentifier("password.form.new")
        SecureField("Confirmar nova senha", text: $confirmPassword)
          .textContentType(.newPassword)
          .focused($focusedField, equals: .confirmation)
          .accessibilityFocused($accessibilityFocusedField, equals: .confirmation)
          .accessibilityIdentifier("password.form.confirmation")
        if let validationMessage { errorLabel(validationMessage) }
      }
    case .review:
      RentivoWizardSection("Confirmação de segurança") {
        Label(
          "Sua senha atual e a nova senha foram preenchidas. Por segurança, os valores não são exibidos nesta revisão.",
          systemImage: "lock.shield.fill"
        )
        .foregroundStyle(RentivoColors.secondaryInk)
        .accessibilityIdentifier("password.review.redacted")
      }
      if let validationMessage {
        RentivoWizardSection("Não foi possível alterar") {
          errorLabel(validationMessage)
        }
      }
    }
  }

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("password.form.error")
  }

  private func validateCurrentStep() -> Bool {
    validationMessage = nil
    switch step {
    case .current:
      guard !currentPassword.isEmpty else {
        validationMessage = "Informe sua senha atual."
        scheduleFocus(.current)
        return false
      }
      guard BcryptPasswordRules.isAccepted(currentPassword) else {
        validationMessage = BcryptPasswordRules.limitMessage
        scheduleFocus(.current)
        return false
      }
    case .new:
      guard !newPassword.isEmpty, !confirmPassword.isEmpty else {
        validationMessage = "Informe e confirme a nova senha."
        scheduleFocus(newPassword.isEmpty ? .new : .confirmation)
        return false
      }
      guard BcryptPasswordRules.isAccepted(newPassword) else {
        validationMessage = BcryptPasswordRules.limitMessage
        scheduleFocus(.new)
        return false
      }
      guard newPassword == confirmPassword else {
        validationMessage = "As senhas não coincidem."
        scheduleFocus(.confirmation)
        return false
      }
    case .review:
      break
    }
    return true
  }

  private func save() {
    guard !isSaving else { return }
    guard BcryptPasswordRules.isAccepted(currentPassword) else {
      validationMessage = currentPassword.isEmpty
        ? "Informe sua senha atual." : BcryptPasswordRules.limitMessage
      step = .current
      scheduleFocus(.current)
      return
    }
    guard !newPassword.isEmpty, !confirmPassword.isEmpty else {
      validationMessage = "Informe e confirme a nova senha."
      step = .new
      scheduleFocus(newPassword.isEmpty ? .new : .confirmation)
      return
    }
    guard BcryptPasswordRules.isAccepted(newPassword) else {
      validationMessage = BcryptPasswordRules.limitMessage
      step = .new
      scheduleFocus(.new)
      return
    }
    guard newPassword == confirmPassword else {
      validationMessage = "As senhas não coincidem."
      step = .new
      scheduleFocus(.confirmation)
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

  private func scheduleFocus(_ field: Field) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
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
              .padding()
              .frame(maxWidth: .infinity)
              .background(RentivoColors.surface)
              .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }
        HStack {
          Button {
            UIPasteboard.general.string = codes.joined(separator: "\n")
          } label: {
            Label("Copiar códigos", systemImage: "doc.on.doc")
          }
          ShareLink(item: codes.joined(separator: "\n")) {
            Label("Compartilhar", systemImage: "square.and.arrow.up")
          }
        }
        Spacer()
      }
      .padding(RentivoSpacing.page)
      .background(RentivoColors.paper)
      .navigationTitle("Recuperação")
      .toolbar { Button("Concluir") { dismiss() } }
    }
  }
}

private struct TOTPEnrollmentView: View {
  @Environment(\.dismiss) private var dismiss
  let enrollment: TOTPEnrollment
  /// Returns the failure message when the code is rejected, or `nil` once the enrollment is
  /// confirmed. The sheet stays open on failure, so the message is rendered here rather than in
  /// the global notice banner behind it.
  let onConfirm: (String) async -> String?
  @State private var code = ""
  @State private var errorMessage: String?
  @State private var isConfirming = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        Label("Configure seu autenticador", systemImage: "qrcode")
          .font(RentivoTypography.title)
        Text("Adicione esta chave manualmente ao seu aplicativo autenticador e informe o código de seis dígitos.")
        Text(enrollment.secret)
          .font(.system(.body, design: .monospaced, weight: .bold))
          .textSelection(.enabled)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RentivoColors.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12))
        TextField("Código do autenticador", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .onChange(of: code) { _, value in
            code = String(value.filter(\.isNumber).prefix(6))
          }
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("security.totp.error")
        }
        Button(action: confirm) {
          HStack(spacing: RentivoSpacing.small) {
            if isConfirming {
              ProgressView()
                .tint(.white)
            }
            Text("Confirmar")
          }
        }
        .buttonStyle(RentivoButtonStyle())
        .disabled(isConfirming || code.count != 6)
        Spacer()
      }
      .padding(RentivoSpacing.page)
      .background(RentivoColors.paper)
      .navigationTitle("Autenticador")
      .toolbar {
        Button("Cancelar") { dismiss() }
          .disabled(isConfirming)
      }
    }
  }

  private func confirm() {
    guard !isConfirming else { return }
    errorMessage = nil
    isConfirming = true
    Task {
      defer { isConfirming = false }
      errorMessage = await onConfirm(code)
    }
  }
}

extension Date {
  /// Formats this date pinned to the pt-BR locale, so PT-BR sentences never leak a
  /// device-locale date string (e.g. "Jul 23, 2026" showing up on an en-US device
  /// inside otherwise-Portuguese copy).
  func formattedPTBR(
    date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
    time timeStyle: Date.FormatStyle.TimeStyle = .omitted
  ) -> String {
    formatted(Date.FormatStyle(date: dateStyle, time: timeStyle, locale: Locale(identifier: "pt_BR")))
  }
}
