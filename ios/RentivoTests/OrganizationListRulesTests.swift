import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func organizationListShowsTheEmptyStateWithoutOrganizationsOrInvitations() {
    #expect(
      OrganizationListRules.showsEmptyState(organizationCount: 0, pendingInvitationCount: 0)
    )
  }

  @Test func organizationListRendersContentWhenAnInvitationIsPendingWithoutOrganizations() {
    // The "Convites pendentes" banner only exists inside the loaded-content closure, so an
    // invitee with no organizations must not be routed to the empty state.
    #expect(
      !OrganizationListRules.showsEmptyState(organizationCount: 0, pendingInvitationCount: 1)
    )
    #expect(
      !OrganizationListRules.showsEmptyState(organizationCount: 0, pendingInvitationCount: 5)
    )
  }

  @Test func organizationListRendersContentWheneverOrganizationsExist() {
    #expect(
      !OrganizationListRules.showsEmptyState(organizationCount: 1, pendingInvitationCount: 0)
    )
    #expect(
      !OrganizationListRules.showsEmptyState(organizationCount: 3, pendingInvitationCount: 2)
    )
  }

  @Test func organizationListEmptyHintInvitesAcceptanceAndOffersCreationWhenAllowed() {
    #expect(
      OrganizationListRules.emptyListHint(canCreateOrganization: true)
        == "Aceite um convite pendente para entrar em uma organização, ou crie a sua para começar do zero."
    )
    #expect(
      OrganizationListRules.emptyListHint(canCreateOrganization: false)
        == "Aceite um convite pendente para entrar em uma organização."
    )
  }
#endif
