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
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization
  let onSaved: () async -> Void
  @State private var email = ""
  @State private var role: OrganizationRole = .viewer
  /// Server-side rejection (e.g. a 422 on the e-mail) for the last submit. This form is presented
  /// in a sheet and the global notice banner renders behind it, so the message has to stay inline.
  @State private var submitErrorMessage: String?
  @State private var saving = false

  var body: some View {
    Form {
      TextField("E-mail", text: $email)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
      Picker("Função", selection: $role) {
        ForEach(OrganizationRole.allCases, id: \.self) { role in
          Text(role.label).tag(role)
        }
      }
      // This disclosure only describes the mock store's in-memory behavior;
      // against the live API the invite is actually persisted server-side, so
      // showing it there would be misleading demo residue.
      if !app.usesLiveAPI {
        Label("O convite ficará pendente apenas na memória do app.", systemImage: "info.circle")
          .font(.footnote)
      }
      if let submitErrorMessage {
        Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(RentivoColors.coral)
          .accessibilityIdentifier("invite.form.error")
      }
    }
    .navigationTitle("Convidar membro")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }.disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        // The spinner is the only sign the request is still in flight: everything else this form
        // does while saving is a disable, which on a stalled request reads as a frozen sheet.
        Button {
          Task { await invite() }
        } label: {
          HStack(spacing: RentivoSpacing.small) {
            if saving { ProgressView() }
            Text("Convidar")
          }
        }
        .disabled(saving || !OrganizationInviteEmail.isValid(email))
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func invite() async {
    guard !saving else { return }
    if let message = OrganizationInviteEmail.validationMessage(email) {
      submitErrorMessage = message
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
}
