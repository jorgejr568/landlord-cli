import Foundation
import RentivoCore
import SwiftUI
import Testing

@testable import Rentivo

@Suite("Cobrança adaptive columns")
struct BillingAdaptiveColumnsTests {
  @Test("a width at the breakpoint uses two columns")
  func breakpointIsHorizontal() {
    #expect(BillingAdaptiveLayout.axis(for: 880, breakpoint: 880) == .horizontal)
  }

  @Test("a narrow width stacks the columns")
  func narrowWidthIsVertical() {
    #expect(BillingAdaptiveLayout.axis(for: 879, breakpoint: 880) == .vertical)
  }

  @Test("an unusable width stacks safely")
  func unusableWidthIsVertical() {
    #expect(BillingAdaptiveLayout.axis(for: nil, breakpoint: 880) == .vertical)
    #expect(BillingAdaptiveLayout.axis(for: .infinity, breakpoint: 880) == .vertical)
  }
}

private func makeBilling(
  name: String = "Aurora 101",
  description: String = "Aluguel mensal",
  owner: BillingOwner = .user(id: StableID.userAna, name: "Pessoal")
) -> Billing {
  Billing(
    id: StableID.billingAurora101,
    name: name,
    description: description,
    owner: owner,
    items: []
  )
}

private func makeOrganization(id: OrganizationID, name: String) -> Organization {
  Organization(
    id: id,
    name: name,
    pix: nil,
    members: [],
    requiresMFA: false,
    currentUserRole: .admin
  )
}

@Suite("Cobranças portfolio filtering")
struct BillingPortfolioFilteringTests {
  @Test("the owner filter offers the three PT-BR segments in order")
  func ownerFilterSegmentsArePTBR() {
    #expect(BillingOwnerFilter.allCases.map(\.rawValue) == ["Todas", "Pessoais", "Organizações"])
  }

  @Test("each owner segment keeps only the billings it names")
  func ownerFilterMatchesTheSelectedSegment() {
    let personal = makeBilling(owner: .user(id: StableID.userAna, name: "Pessoal"))
    let organization = makeBilling(
      owner: .organization(id: StableID.organizationHorizonte, name: "Horizonte")
    )

    #expect(BillingOwnerFilter.all.matches(personal))
    #expect(BillingOwnerFilter.all.matches(organization))
    #expect(BillingOwnerFilter.personal.matches(personal))
    #expect(!BillingOwnerFilter.personal.matches(organization))
    #expect(BillingOwnerFilter.organization.matches(organization))
    #expect(!BillingOwnerFilter.organization.matches(personal))
  }

  @Test("search matches name, description, and responsible party, ignoring case")
  func searchLooksAtEveryVisibleField() {
    let billing = makeBilling(
      name: "Aurora 101",
      description: "Aluguel mensal",
      owner: .organization(id: StableID.organizationHorizonte, name: "Horizonte")
    )

    #expect(BillingPortfolioSearch.matches(billing, query: "aurora"))
    #expect(BillingPortfolioSearch.matches(billing, query: "ALUGUEL"))
    #expect(BillingPortfolioSearch.matches(billing, query: "horizonte"))
    #expect(!BillingPortfolioSearch.matches(billing, query: "torre norte"))
  }

  @Test("a blank or whitespace-only query matches every billing")
  func blankSearchMatchesEverything() {
    let billing = makeBilling()

    #expect(BillingPortfolioSearch.matches(billing, query: ""))
    #expect(BillingPortfolioSearch.matches(billing, query: "   \n "))
    // Surrounding whitespace must not defeat an otherwise matching query either.
    #expect(BillingPortfolioSearch.matches(billing, query: "  aurora  "))
  }
}

@Suite("Cobrança form owner choices")
struct BillingFormOwnerChoicesTests {
  @Test("a new cobrança offers the personal workspace first, then every organization")
  func newBillingListsPersonalThenOrganizations() {
    let choices = BillingFormOwnerChoices.choices(
      currentUserID: StableID.userAna,
      existingOwner: nil,
      organizations: [makeOrganization(id: StableID.organizationHorizonte, name: "Horizonte")]
    )

    #expect(choices.map(\.name) == ["Pessoal", "Horizonte"])
    #expect(choices.first?.id == .personal)
  }

  @Test("the owner a cobrança already has stays selectable even when it is not listed")
  func existingOwnerSurvivesAnEmptyOrganizationList() {
    let existing = BillingOwner.organization(id: StableID.organizationHorizonte, name: "Horizonte")

    let choices = BillingFormOwnerChoices.choices(
      currentUserID: StableID.userAna,
      existingOwner: existing,
      organizations: []
    )

    #expect(choices.map(\.name) == ["Pessoal", "Horizonte"])
  }

  @Test("an organization that is also the current owner is listed once")
  func currentOwnerIsNotDuplicatedByTheOrganizationList() {
    let existing = BillingOwner.organization(id: StableID.organizationHorizonte, name: "Horizonte")

    let choices = BillingFormOwnerChoices.choices(
      currentUserID: StableID.userAna,
      existingOwner: existing,
      organizations: [makeOrganization(id: StableID.organizationHorizonte, name: "Horizonte")]
    )

    #expect(choices.count == 2)
    #expect(choices.filter { $0.id == existing.id }.count == 1)
  }

  @Test("a personal cobrança does not duplicate the personal workspace")
  func personalOwnerIsNotDuplicated() {
    let choices = BillingFormOwnerChoices.choices(
      currentUserID: StableID.userAna,
      existingOwner: .user(id: StableID.userAna, name: "Pessoal"),
      organizations: []
    )

    #expect(choices.count == 1)
  }
}

@Suite("Cobrança PIX override validation")
struct BillingPixOverrideTests {
  @Test("no PIX key means the cobrança inherits, with nothing to review")
  func emptyKeyInherits() {
    let resolution = BillingPixOverride.resolve(key: "  ", merchantName: "", merchantCity: "")

    #expect(resolution.configuration == nil)
    #expect(resolution.message == nil)
  }

  @Test("a PIX key without recipient data blocks the save with PT-BR guidance")
  func keyWithoutRecipientDataIsRejected() {
    let resolution = BillingPixOverride.resolve(
      key: "chave@rentivo.com.br", merchantName: "Ana", merchantCity: "  "
    )

    #expect(resolution.configuration == nil)
    #expect(
      resolution.message
        == "Informe o nome e a cidade do recebedor para usar uma chave PIX própria."
    )
  }

  @Test("a complete PIX override is trimmed before it reaches the draft")
  func completeOverrideIsTrimmed() throws {
    let resolution = BillingPixOverride.resolve(
      key: "  chave@rentivo.com.br ", merchantName: " Ana Souza ", merchantCity: " SAO PAULO "
    )

    let configuration = try #require(resolution.configuration)
    #expect(resolution.message == nil)
    #expect(configuration.key == "chave@rentivo.com.br")
    #expect(configuration.merchantName == "Ana Souza")
    #expect(configuration.merchantCity == "SAO PAULO")
    #expect(configuration.isComplete)
  }
}

@Suite("Cobrança form editable rows")
struct BillingFormEditableRowTests {
  @Test("an untouched recipient row is dropped rather than reported as invalid")
  func blankRecipientIsRecognized() {
    #expect(EditableRecipient().isBlank)

    var partial = EditableRecipient()
    partial.email = "ana@rentivo.com.br"
    #expect(!partial.isBlank)
  }

  @Test("a recipient's name and e-mail are trimmed on the way to the draft")
  func recipientIsTrimmed() {
    var recipient = EditableRecipient()
    recipient.name = "  Ana Souza "
    recipient.email = " ana@rentivo.com.br  "

    let domain = recipient.domain()

    #expect(domain.name == "Ana Souza")
    #expect(domain.email == "ana@rentivo.com.br")
    #expect(domain.id == recipient.id)
  }

  @Test("an edited item keeps its identity and carries its row position as the sort order")
  func editableItemRoundTripsThroughTheDomain() {
    let original = BillingItem(
      id: BillingItemID(rawValue: "item-1"),
      description: "Aluguel",
      amount: Money(centavos: 245_000),
      type: .fixed,
      sortOrder: 0
    )

    var editable = EditableBillingItem(item: original)
    editable.centavos = 250_000

    let domain = editable.domain(sortOrder: 3)

    #expect(domain.id == original.id)
    #expect(domain.description == "Aluguel")
    #expect(domain.amount == Money(centavos: 250_000))
    #expect(domain.type == .fixed)
    #expect(domain.sortOrder == 3)
  }

  @Test("a malformed variable item is zeroed when it enters editable form state")
  func variableItemIsNormalizedForEditing() {
    let original = BillingItem(
      id: BillingItemID(rawValue: "item-variable"),
      description: "Água",
      amount: Money(centavos: 5_000),
      type: .variable,
      sortOrder: 0
    )

    let editable = EditableBillingItem(item: original)

    #expect(editable.id == original.id)
    #expect(editable.type == .variable)
    #expect(editable.centavos == 0)
  }

  @Test("a brand-new item starts blank and mints its own identity")
  func newEditableItemStartsBlank() {
    let first = EditableBillingItem(type: .variable)
    let second = EditableBillingItem(type: .variable)

    #expect(first.description.isEmpty)
    #expect(first.centavos == 0)
    #expect(first.type == .variable)
    #expect(first.id != second.id)
  }
}
