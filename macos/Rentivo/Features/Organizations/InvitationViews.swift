import RentivoCore
import SwiftUI

struct InvitationListView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let onMutation: () async -> Void
  @State private var state: LoadState<[Invitation]> = .idle
  @State private var respondingID: InvitationID?
  @State private var respondFailureMessage: String?

  var body: some View {
    PageStateView(
      state: state,
      emptyTitle: "Nenhum convite pendente",
      emptyMessage: "Convites para participar de organizações aparecerão aqui assim que alguém te convidar.",
      emptySystemImage: "envelope.open"
    ) { invitations in
      List {
        if let respondFailureMessage {
          Section {
            Label(respondFailureMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("invitation.respond.error")
          }
        }
        ForEach(invitations) { invitation in
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            Text(invitation.organizationName).font(RentivoTypography.cardTitle)
            Label(invitation.role.label, systemImage: "person.badge.shield.checkmark")
              .font(RentivoTypography.caption)
            if let invitedByEmail = invitation.invitedByEmail {
              Label("Convidado por \(invitedByEmail)", systemImage: "envelope.fill")
                .font(RentivoTypography.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
            if invitation.organizationEnforcesMFA {
              Label("Esta organização exige MFA.", systemImage: "lock.shield.fill")
                .font(RentivoTypography.metadata)
                .foregroundStyle(RentivoColors.coral)
                .accessibilityIdentifier("invitation.mfa.required")
            }
            if !app.usesLiveAPI && app.demoSettings.viewerMode {
              Label("Ações indisponíveis no modo visualizador.", systemImage: "eye.fill")
                .font(RentivoTypography.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            } else {
              HStack {
                Button("Aceitar") { Task { await respond(invitation, accept: true) } }
                  .buttonStyle(.borderedProminent)
                Button("Recusar", role: .destructive) {
                  Task { await respond(invitation, accept: false) }
                }
                .buttonStyle(.bordered)
                if respondingID == invitation.id {
                  ProgressView().controlSize(.small)
                }
              }
              // Both buttons on every row hold while any response is in flight: the answer
              // reshapes the whole list, so a second click would act on a stale row.
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
    state.prepareForRefresh()
    do {
      let invitations = try await app.dependencies.invitations.listPendingInvitations()
      state = invitations.isEmpty ? .empty : .loaded(invitations)
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }

  private func respond(_ invitation: Invitation, accept: Bool) async {
    guard respondingID == nil else { return }
    respondingID = invitation.id
    respondFailureMessage = nil
    defer { respondingID = nil }
    do {
      var acceptance: InvitationAcceptance?
      if accept {
        acceptance = try await app.dependencies.invitations.acceptInvitation(id: invitation.id)
      } else {
        try await app.dependencies.invitations.declineInvitation(id: invitation.id)
      }
      app.showNotice(accept ? "Convite aceito." : "Convite recusado.")
      await load()
      await onMutation()
      if acceptance?.mfaSetupRequired == true {
        dismiss()
        app.selectedTab = .account
        app.showNotice(
          "Sua nova organização exige MFA. Abra Segurança para configurar TOTP ou uma passkey.",
          kind: .warning
        )
      }
    } catch {
      // This whole list is presented as a sheet, and the global banner renders behind it — a
      // failure reported there would read as the button doing nothing at all.
      respondFailureMessage = DemoError(error).message
    }
  }
}

struct InviteMemberView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let organization: Organization
  let onSaved: () async -> Void
  @State private var email = ""
  @State private var role: OrganizationRole = .viewer
  @State private var submitFailureMessage: String?
  @State private var saving = false

  var body: some View {
    Form {
      TextField("E-mail", text: $email)
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
          .font(RentivoTypography.caption)
      }

      if let submitFailureMessage {
        Section {
          Label(submitFailureMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("invitation.form.error")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Convidar membro")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }.disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Convidar") { Task { await invite() } }
          .disabled(saving || !OrganizationInviteEmail.isValid(email))
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func invite() async {
    // Without this the sheet stays interactive across the round trip and a double-click sends the
    // same person two invitations.
    guard !saving else { return }
    if let message = OrganizationInviteEmail.validationMessage(email) {
      submitFailureMessage = message
      return
    }
    submitFailureMessage = nil
    saving = true
    defer { saving = false }
    do {
      _ = try await app.dependencies.organizations.inviteMember(
        organizationID: organization.id,
        email: OrganizationInviteEmail.normalized(email),
        role: role
      )
      // The notice outlives the sheet — `app.notice` holds it until the banner is dismissed — so
      // setting it just before `dismiss()` still leaves it visible once the sheet is gone.
      app.showNotice("Convite enviado.")
      await onSaved()
      dismiss()
    } catch {
      // The global banner renders behind this sheet, so a failure reported there would read as
      // Convidar doing nothing at all. Keep it inline, where the user is looking.
      submitFailureMessage = DemoError(error).message
    }
  }
}
