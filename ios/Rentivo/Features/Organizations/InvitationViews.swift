import SwiftUI

struct InvitationListView: View {
  @Environment(AppModel.self) private var app
  let onMutation: () async -> Void
  @State private var state: LoadState<[Invitation]> = .idle
  /// Failures raised while the sheet is open (a refresh or an accept/decline) are shown as a row
  /// in the list: the global notice banner lives on `RootView`, behind this sheet.
  @State private var errorMessage: String?
  /// The invitation whose accept/decline is in flight, so its row can show progress and every
  /// button stays disabled until the response lands.
  @State private var respondingID: InvitationID?

  var body: some View {
    PageStateView(
      state: state,
      emptyTitle: "Nenhum convite pendente",
      emptyMessage: "Convites para participar de organizações aparecerão aqui assim que alguém te convidar.",
      emptySystemImage: "envelope.open"
    ) { invitations in
      List {
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("invitation.error")
        }
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
    .background(RentivoColors.paper)
    .navigationTitle("Convites")
    .task(id: app.dataRevision) { await load() }
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
      errorMessage = nil
      state = invitations.isEmpty ? .empty : .loaded(invitations)
    } catch {
      switch state {
      case .loaded, .empty:
        errorMessage = DemoError(error).message
      default:
        state = .failed(DemoError(error))
      }
    }
  }

  private func respond(_ invitation: Invitation, accept: Bool) async {
    guard respondingID == nil else { return }
    errorMessage = nil
    respondingID = invitation.id
    defer { respondingID = nil }
    do {
      if accept {
        try await app.dependencies.invitations.acceptInvitation(id: invitation.id)
      } else {
        try await app.dependencies.invitations.declineInvitation(id: invitation.id)
      }
      await load()
      await onMutation()
      app.showNotice(accept ? "Convite aceito." : "Convite recusado.")
    } catch { errorMessage = DemoError(error).message }
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
        Button("Convidar") { Task { await invite() } }
          .disabled(saving || !email.contains("@"))
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func invite() async {
    guard !saving else { return }
    submitErrorMessage = nil
    saving = true
    defer { saving = false }
    do {
      _ = try await app.dependencies.organizations.inviteMember(
        organizationID: organization.id,
        email: email,
        role: role
      )
      await onSaved()
      dismiss()
      app.showNotice("Convite enviado.")
    } catch { submitErrorMessage = DemoError(error).message }
  }
}
