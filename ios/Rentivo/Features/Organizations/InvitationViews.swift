import SwiftUI

struct InvitationListView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let onMutation: () async -> Void
  @State private var state: LoadState<[Invitation]> = .idle
  /// What the last refresh or accept/decline has to say, shown above the list: the global notice
  /// banner lives on `RootView`, behind this sheet, so neither a failure nor a confirmation would
  /// be visible there while the sheet is open.
  @State private var notice: InlineNotice?
  /// The invitation whose accept/decline is in flight, so its row can show progress and every
  /// button stays disabled until the response lands.
  @State private var respondingID: InvitationID?

  /// A message rendered in the slot above the list. It sits *outside* `PageStateView` because a
  /// refresh can fail while the list is empty, and the empty state renders none of the content
  /// closure — the failure would have been swallowed behind "Nenhum convite pendente".
  private enum InlineNotice {
    case failure(String)
    case confirmation(String)

    var message: String {
      switch self {
      case .failure(let message), .confirmation(let message): message
      }
    }

    var systemImage: String {
      switch self {
      case .failure: "exclamationmark.circle.fill"
      case .confirmation: "checkmark.circle.fill"
      }
    }

    var tint: Color {
      switch self {
      case .failure: RentivoColors.coral
      case .confirmation: RentivoColors.emerald
      }
    }

    var accessibilityIdentifier: String {
      switch self {
      case .failure: "invitation.error"
      case .confirmation: "invitation.confirmation"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if let notice {
        Label(notice.message, systemImage: notice.systemImage)
          .font(.subheadline)
          .foregroundStyle(notice.tint)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, RentivoSpacing.large)
          .padding(.top, RentivoSpacing.medium)
          .accessibilityIdentifier(notice.accessibilityIdentifier)
      }
      content
    }
    .background(RentivoColors.paper)
    .navigationTitle("Convites")
    .task(id: app.dataRevision) { await load() }
  }

  private var content: some View {
    PageStateView(
      state: state,
      emptyTitle: "Nenhum convite pendente",
      emptyMessage: "Convites para participar de organizações aparecerão aqui assim que alguém te convidar.",
      emptySystemImage: "envelope.open"
    ) { invitations in
      List {
        ForEach(invitations) { invitation in
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            Text(invitation.organizationName).font(.headline)
            Label(invitation.role.label, systemImage: "person.badge.shield.checkmark")
              .font(.caption)
            if let invitedByEmail = invitation.invitedByEmail {
              Label("Convidado por \(invitedByEmail)", systemImage: "envelope.fill")
                .font(.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
            if invitation.organizationEnforcesMFA {
              Label("Esta organização exige MFA.", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RentivoColors.coral)
                .accessibilityIdentifier("invitation.mfa.required")
            }
            if !app.usesLiveAPI && app.demoSettings.viewerMode {
              Label("Ações indisponíveis no modo visualizador.", systemImage: "eye.fill")
                .font(.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            } else {
              HStack(spacing: RentivoSpacing.small) {
                Button("Aceitar") { Task { await respond(invitation, accept: true) } }
                  .buttonStyle(.borderedProminent)
                Button("Recusar", role: .destructive) {
                  Task { await respond(invitation, accept: false) }
                }
                .buttonStyle(.bordered)
                if respondingID == invitation.id {
                  ProgressView()
                }
              }
              .disabled(respondingID != nil)
            }
          }
          .padding(.vertical, RentivoSpacing.small)
        }
      }
      .scrollContentBackground(.hidden)
    } retry: {
      await load()
    }
  }

  private func load() async {
    // Only blank the sheet with a spinner on first load; a `dataRevision`
    // bump while the sheet is open (e.g. toggling a demo setting) refreshes
    // in place instead of tearing down the currently-shown list.
    switch state {
    case .idle, .failed:
      state = .loading
    case .loading, .loaded, .empty:
      break
    }
    do {
      let invitations = try await app.dependencies.invitations.listPendingInvitations()
      notice = nil
      state = invitations.isEmpty ? .empty : .loaded(invitations)
    } catch {
      switch state {
      case .loaded, .empty:
        notice = .failure(DemoError(error).message)
      default:
        state = .failed(DemoError(error))
      }
    }
  }

  private func respond(_ invitation: Invitation, accept: Bool) async {
    guard respondingID == nil else { return }
    notice = nil
    respondingID = invitation.id
    defer { respondingID = nil }
    do {
      var acceptance: InvitationAcceptance?
      if accept {
        acceptance = try await app.dependencies.invitations.acceptInvitation(id: invitation.id)
      } else {
        try await app.dependencies.invitations.declineInvitation(id: invitation.id)
      }
      await load()
      await onMutation()
      if acceptance?.mfaSetupRequired == true {
        dismiss()
        app.selectedTab = .account
        app.showNotice(
          "Sua nova organização exige MFA. Abra Segurança para configurar TOTP ou uma passkey.",
          kind: .warning
        )
        return
      }
      // The confirmation goes in the same slot as a failure rather than through `app.showNotice`:
      // the global banner would render behind this sheet and the user would never see it.
      notice = .confirmation(accept ? "Convite aceito." : "Convite recusado.")
    } catch { notice = .failure(DemoError(error).message) }
  }
}

struct InviteMemberView: View {
  private enum Step: CaseIterable {
    case person
    case permission
    case review
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization
  let onSaved: () async -> Void
  @State private var email = ""
  @State private var role: OrganizationRole = .viewer
  @State private var emailValidationMessage: String?
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var step: Step = .person
  @FocusState private var emailIsFocused: Bool
  @AccessibilityFocusState private var emailIsAccessibilityFocused: Bool

  var body: some View {
    RentivoFormWizard(
      title: "Convidar membro",
      descriptors: descriptors,
      selectedStep: $step,
      isBusy: saving,
      finalActionTitle: "Enviar convite",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: { Task { await invite() } }
    ) { selectedStep in
      stepContent(selectedStep)
    }
    .interactiveDismissDisabled(!email.isEmpty || role != .viewer || saving)
  }

  private var descriptors: [RentivoWizardStepDescriptor<Step>] {
    [
      .init(id: .person, title: "Pessoa"),
      .init(id: .permission, title: "Permissão"),
      .init(id: .review, title: "Revisão"),
    ]
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .person:
      RentivoWizardSection(
        "Quem você quer convidar?",
        subtitle: "O convite será enviado para este endereço."
      ) {
        RentivoTextFormField(
          label: "E-mail",
          text: $email,
          errorMessage: emailValidationMessage,
          isFocused: Binding(
            get: { emailIsFocused },
            set: { emailIsFocused = $0 }
          ),
          isAccessibilityFocused: Binding(
            get: { emailIsAccessibilityFocused },
            set: { emailIsAccessibilityFocused = $0 }
          ),
          accessibilityIdentifier: "invite.form.email"
        )
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: email) {
            if emailValidationMessage != nil {
              emailValidationMessage = OrganizationInviteEmail.validationMessage(email)
            }
          }
      }
    case .permission:
      RentivoWizardSection(
        "Permissão na organização",
        subtitle: "Escolha o que esta pessoa poderá consultar e alterar."
      ) {
        RentivoFormField(label: "Função") {
          Picker("", selection: $role) {
            ForEach(OrganizationRole.allCases, id: \.self) { role in
              Text(role.label).tag(role)
            }
          }
          .labelsHidden()
          .accessibilityLabel("Função")
          .accessibilityIdentifier("invite.form.role")
        }
        if organization.requiresMFA {
          Label(
            "Esta organização exige MFA. A pessoa precisará configurar um fator de autenticação ao aceitar o convite.",
            systemImage: "lock.shield.fill"
          )
          .font(.footnote)
          .foregroundStyle(RentivoColors.coral)
          .accessibilityIdentifier("invite.mfa.consequence")
        } else {
          Label(
            "A autenticação multifator é opcional nesta organização.",
            systemImage: "lock.open"
          )
          .font(.footnote)
          .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      if !app.usesLiveAPI {
        RentivoWizardSection("Demonstração") {
          Label("O convite ficará pendente apenas na memória do app.", systemImage: "info.circle")
            .font(.footnote)
        }
      }
    case .review:
      RentivoWizardSection("Convite") {
        RentivoWizardReviewRow(label: "E-mail", value: OrganizationInviteEmail.normalized(email))
        RentivoWizardReviewRow(label: "Função", value: role.label)
        RentivoWizardReviewRow(
          label: "MFA", value: organization.requiresMFA ? "Obrigatório" : "Opcional"
        )
      }
      if let submitErrorMessage {
        RentivoWizardSection("Não foi possível convidar") {
          errorLabel(submitErrorMessage)
        }
      }
    }
  }

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("invite.form.error")
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    guard step == .person else { return true }
    emailValidationMessage = OrganizationInviteEmail.validationMessage(email)
    if emailValidationMessage != nil { scheduleEmailFocus() }
    return emailValidationMessage == nil
  }

  private func invite() async {
    guard !saving else { return }
    if let message = OrganizationInviteEmail.validationMessage(email) {
      emailValidationMessage = message
      step = .person
      scheduleEmailFocus()
      return
    }
    submitErrorMessage = nil
    saving = true
    defer { saving = false }
    do {
      _ = try await app.dependencies.organizations.inviteMember(
        organizationID: organization.id,
        email: OrganizationInviteEmail.normalized(email),
        role: role
      )
      await onSaved()
      dismiss()
      app.showNotice("Convite enviado.")
    } catch { submitErrorMessage = DemoError(error).message }
  }

  private func scheduleEmailFocus() {
    Task { @MainActor in
      emailIsFocused = true
      emailIsAccessibilityFocused = true
    }
  }
}
