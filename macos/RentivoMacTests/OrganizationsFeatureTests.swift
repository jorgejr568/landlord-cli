import RentivoCore
import Testing

@testable import Rentivo

@Suite("macOS organization form validation")
struct OrganizationFormValidationTests {
  @Test("a blank PIX key means no PIX at all, so the recipient fields stay optional")
  func blankKeyNeedsNoRecipient() {
    #expect(OrganizationFormValidation.pixMessage(key: "", merchantName: "", city: "") == nil)
  }

  @Test("a PIX key without a recipient name or city is rejected")
  func keyWithoutRecipientIsRejected() {
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: "", city: "SALVADOR"
      ) == "Informe o nome do recebedor."
    )
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: "ANA", city: ""
      ) == "Informe a cidade do recebedor."
    )
  }

  @Test("recipient name and city respect the server's column limits")
  func recipientFieldsRespectServerColumnLimits() {
    // The follow-up PATCH caps `pix_merchant_name` and `pix_merchant_city` at 255, so the form
    // has to reject over-long values rather than let the request 422.
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: String(repeating: "A", count: 255),
        city: String(repeating: "B", count: 255)
      ) == nil
    )
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: String(repeating: "A", count: 256),
        city: "SALVADOR"
      ) == "O nome do recebedor deve ter até 255 caracteres."
    )
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: "ANA", city: String(repeating: "B", count: 256)
      ) == "A cidade do recebedor deve ter até 255 caracteres."
    )
    let combiningCharacter = "e\u{301}"
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: String(repeating: "😀", count: 255),
        city: String(repeating: "😀", count: 255)
      ) == nil
    )
    #expect(
      OrganizationFormValidation.pixMessage(
        key: "ana@example.com", merchantName: String(repeating: combiningCharacter, count: 128),
        city: "SALVADOR"
      ) == "O nome do recebedor deve ter até 255 caracteres."
    )
  }

  @Test("an untouched unclassified legacy key survives an organization rename")
  func untouchedLegacyKeyIsPreserved() throws {
    let editor = MacOSPixKeyEditor(persistedKey: "chave-legada")

    let result = OrganizationFormValidation.pixResult(
      editor: editor, merchantName: " LOCADOR ", city: " RECIFE "
    )

    guard case .custom(let configuration) = result else {
      Issue.record("Expected the untouched persisted PIX configuration to remain custom")
      return
    }
    #expect(configuration.key == "chave-legada")
    #expect(configuration.merchantName == "LOCADOR")
    #expect(configuration.merchantCity == "RECIFE")
  }
}

@Suite("macOS organization billing index")
struct OrganizationBillingIndexTests {
  private func billing(_ id: String, owner: BillingOwner) -> Billing {
    Billing(
      id: BillingID(rawValue: id), name: id, description: "", owner: owner, items: []
    )
  }

  @Test("an organization's cobranças are keyed by the organization's own identifier")
  func organizationBillingsAreKeyedByOrganizationID() {
    // The list screen counts, and the detail screen lists, through this key. `BillingOwner`
    // derives the workspace key from the organization's raw identifier, so the two sides only meet
    // if `workspaceID(of:)` derives it the same way.
    let organizationID = OrganizationID(rawValue: "org-horizonte")
    let owned = billing("b1", owner: .organization(id: organizationID, name: "Horizonte"))
    let personal = billing("b2", owner: .user(id: 7, name: "Pessoal"))

    let index = OrganizationBillingIndex.byWorkspace([owned, personal])

    #expect(index[OrganizationBillingIndex.workspaceID(of: organizationID)] == [owned])
    #expect(index[.personal] == [personal])
  }

  @Test("an organization with no cobranças has no entry, which reads as a count of zero")
  func organizationsWithoutBillingsAreAbsent() {
    let index = OrganizationBillingIndex.byWorkspace([
      billing("b1", owner: .user(id: 7, name: "Pessoal"))
    ])

    let empty = OrganizationBillingIndex.workspaceID(of: OrganizationID(rawValue: "org-vazia"))
    #expect(index[empty] == nil)
    #expect((index[empty] ?? []).count == 0)
  }

  @Test("only capability-authorized personal cobranças are offered for transfer")
  func personalBillingsRequireTransferCapability() {
    let owned = billing(
      "b1", owner: .organization(id: OrganizationID(rawValue: "org-horizonte"), name: "Horizonte")
    )
    let personal = billing("b2", owner: .user(id: 7, name: "Pessoal"))
    var denied = billing("b3", owner: .user(id: 7, name: "Pessoal"))
    denied.capabilities = .viewer

    #expect(OrganizationBillingIndex.personal([owned, denied, personal]) == [personal])
  }

  @Test("grouping agrees with the per-organization filter it replaced")
  @MainActor
  func groupingAgreesWithTheFilterItReplaced() async throws {
    // The screens used to filter the whole portfolio once per organization. The counts have to be
    // identical against the canonical fixtures, not just against hand-built owners.
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organizations = try await app.dependencies.organizations.listOrganizations()
    let billings = try await app.dependencies.billings.listBillings()

    let index = OrganizationBillingIndex.byWorkspace(billings)

    #expect(organizations.isEmpty == false)
    for organization in organizations {
      let filtered = billings.filter {
        $0.owner.workspaceID.rawValue == organization.id.rawValue
      }
      let grouped = index[OrganizationBillingIndex.workspaceID(of: organization.id)] ?? []
      #expect(grouped == filtered)
    }
  }
}

@Suite("macOS organization member actions")
struct OrganizationMemberActionsTests {
  @Test("the role menu offers every backend role except the member's current role")
  func assignableRolesExcludeOnlyTheCurrentRole() {
    #expect(OrganizationMemberActions.assignableRoles(excluding: .viewer) == [.admin, .manager])
    #expect(OrganizationMemberActions.assignableRoles(excluding: .manager) == [.admin, .viewer])
    #expect(OrganizationMemberActions.assignableRoles(excluding: .admin) == [.manager, .viewer])
  }
}

@Suite("macOS organization capability gating")
@MainActor
struct OrganizationCapabilityGatingTests {
  @Test("an admin sees full capabilities and can rename the organization")
  func adminCanManageTheirOrganization() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )
    #expect(organization.currentUserRole == .admin)
    #expect(organization.capabilities.canManage)
    #expect(organization.capabilities.canInvite)

    let renamed = try await app.dependencies.organizations.updateOrganization(
      id: organization.id,
      draft: OrganizationDraft(name: "Imobiliária Horizonte Sul", pix: organization.pix)
    )

    #expect(renamed.name == "Imobiliária Horizonte Sul")
  }

  @Test("demo viewer mode downgrades the role and blocks every organization mutation")
  func viewerModeDowngradesCapabilitiesAndBlocksMutations() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organizationID = try #require(
      await app.dependencies.organizations.listOrganizations().first?.id
    )
    app.setViewerMode(true)

    let restricted = try await app.dependencies.organizations.organization(id: organizationID)
    #expect(restricted.currentUserRole == .viewer)
    #expect(restricted.capabilities.canManage == false)
    #expect(restricted.capabilities.canInvite == false)

    // The list screen hides "Criar organização" on exactly this condition, and the store agrees:
    // the call is refused rather than silently succeeding behind a hidden button.
    #expect(app.usesLiveAPI == false)
    #expect(app.demoSettings.viewerMode)
    await #expect(throws: DemoError.permissionDenied) {
      try await app.dependencies.organizations.createOrganization(
        OrganizationDraft(name: "Nova", pix: nil)
      )
    }
    await #expect(throws: DemoError.permissionDenied) {
      _ = try await app.dependencies.organizations.setOrganizationMFA(
        organizationID: organizationID, required: false
      )
    }
  }

  @Test("changing a member's role writes through to the reloaded organization")
  func changingAMemberRoleWritesThrough() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )
    let viewer = try #require(organization.members.first { $0.role == .viewer })

    try await app.dependencies.organizations.updateMemberRole(
      organizationID: organization.id, userID: viewer.userID, role: .manager
    )

    let reloaded = try await app.dependencies.organizations.organization(id: organization.id)
    #expect(reloaded.members.first { $0.userID == viewer.userID }?.role == .manager)
  }

  @Test("removing a member drops them from the organization")
  func removingAMemberDropsThem() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )
    let viewer = try #require(organization.members.first { $0.role == .viewer })

    try await app.dependencies.organizations.removeMember(
      organizationID: organization.id, userID: viewer.userID
    )

    let reloaded = try await app.dependencies.organizations.organization(id: organization.id)
    #expect(reloaded.members.contains { $0.userID == viewer.userID } == false)
  }

  @Test("the MFA toggle flips the stored policy")
  func togglingMFAFlipsTheStoredPolicy() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )
    #expect(organization.requiresMFA)

    _ = try await app.dependencies.organizations.setOrganizationMFA(
      organizationID: organization.id, required: false
    )

    let reloaded = try await app.dependencies.organizations.organization(id: organization.id)
    #expect(reloaded.requiresMFA == false)
  }
}

@Suite("macOS invitation responses")
@MainActor
struct InvitationResponseTests {
  @Test("accepting an invitation clears it from the pending list and joins the organization")
  func acceptingAnInvitationJoinsTheOrganization() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let invitation = try #require(
      await app.dependencies.invitations.listPendingInvitations().first
    )
    #expect(invitation.role == .manager)

    try await app.dependencies.invitations.acceptInvitation(id: invitation.id)

    #expect(try await app.dependencies.invitations.listPendingInvitations().isEmpty)
    // The organization was previously invisible to this user (they weren't a member), so it
    // appearing in the list is what proves the acceptance took effect.
    let joined = try await app.dependencies.organizations.listOrganizations()
      .first { $0.id == invitation.organizationID }
    #expect(joined?.currentUserRole == .manager)
  }

  @Test("declining an invitation clears it without joining the organization")
  func decliningAnInvitationLeavesMembershipAlone() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let invitation = try #require(
      await app.dependencies.invitations.listPendingInvitations().first
    )

    try await app.dependencies.invitations.declineInvitation(id: invitation.id)

    #expect(try await app.dependencies.invitations.listPendingInvitations().isEmpty)
    let organizations = try await app.dependencies.organizations.listOrganizations()
    #expect(organizations.contains { $0.id == invitation.organizationID } == false)
  }

  @Test("demo viewer mode refuses to accept or decline")
  func viewerModeRefusesInvitationResponses() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let invitation = try #require(
      await app.dependencies.invitations.listPendingInvitations().first
    )
    app.setViewerMode(true)

    await #expect(throws: DemoError.permissionDenied) {
      try await app.dependencies.invitations.acceptInvitation(id: invitation.id)
    }
    await #expect(throws: DemoError.permissionDenied) {
      try await app.dependencies.invitations.declineInvitation(id: invitation.id)
    }
    #expect(try await app.dependencies.invitations.listPendingInvitations().count == 1)
  }

  @Test("inviting a member adds a pending invitation for that organization")
  func invitingAMemberCreatesAPendingInvitation() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )

    let invitation = try await app.dependencies.organizations.inviteMember(
      organizationID: organization.id, email: "novo@example.com", role: .viewer
    )

    #expect(invitation.status == .pending)
    #expect(invitation.organizationName == organization.name)
    let pending = try await app.dependencies.invitations.listPendingInvitations()
    #expect(pending.contains { $0.id == invitation.id })
  }

  @Test("an address without an @ is refused, matching the sheet's disabled Convidar button")
  func invitingWithoutAnAtSignIsRefused() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let organization = try #require(
      await app.dependencies.organizations.listOrganizations().first
    )

    await #expect(throws: DemoError.operationFailed) {
      try await app.dependencies.organizations.inviteMember(
        organizationID: organization.id, email: "sem-arroba", role: .viewer
      )
    }
  }
}
