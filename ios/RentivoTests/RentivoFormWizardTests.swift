import Testing

#if !canImport(RentivoCore)
  @testable import Rentivo

  private enum Probe: Hashable {
    case first
    case second
    case review
  }

  @Test func wizardFlowAdvancesRetreatsAndClampsAtItsBounds() {
    var flow = RentivoWizardFlow(steps: [Probe.first, .second, .review])
    #expect(flow.progressLabel == "Etapa 1 de 3")
    #expect(flow.retreat() == false)
    #expect(flow.advance() == true)
    #expect(flow.current == .second)
    #expect(flow.advance() == true)
    #expect(flow.isLast)
    #expect(flow.advance() == false)
  }

  @Test func billValidationFocusRoutesToTheFirstActionableControl() {
    let fixedID = BillLineItemID(rawValue: "fixed")
    let extraID = BillLineItemID(rawValue: "extra")
    let lines = [
      BillLineItem(id: fixedID, description: "Aluguel", amount: Money(centavos: 100_00), kind: .fixed),
      BillLineItem(id: extraID, description: "", amount: .zero, kind: .extra),
    ]

    #expect(billFormFocusTarget(issues: [ValidationIssue(field: .items, message: "")], lines: []) == .addExtra)
    #expect(
      billFormFocusTarget(issues: [ValidationIssue(field: .itemDescription, message: "")], lines: lines)
        == .lineDescription(extraID)
    )
    #expect(
      billFormFocusTarget(issues: [ValidationIssue(field: .itemAmount, message: "")], lines: lines)
        == .lineAmount(extraID)
    )
  }

  @Test func expenseValidationFocusRoutesToTheInvalidStepControl() {
    #expect(expenseFormFocusTarget(step: .details, descriptionIsValid: false, centavos: 100) == .description)
    #expect(expenseFormFocusTarget(step: .valueAndDate, descriptionIsValid: true, centavos: 0) == .amount)
    #expect(expenseFormFocusTarget(step: .review, descriptionIsValid: true, centavos: 100) == nil)
  }

  @Test func asyncWizardLoadsApplyOnlyToTheUnchangedDraftThatStartedTheRequest() {
    #expect(
      RentivoAsyncDraftLoadRules.shouldApply(
        requestDraft: "original",
        currentDraft: "original",
        requestRevision: 7,
        currentRevision: 7
      )
    )
    #expect(
      !RentivoAsyncDraftLoadRules.shouldApply(
        requestDraft: "original",
        currentDraft: "edited",
        requestRevision: 7,
        currentRevision: 7
      )
    )
    #expect(
      !RentivoAsyncDraftLoadRules.shouldApply(
        requestDraft: "original",
        currentDraft: "original",
        requestRevision: 7,
        currentRevision: 8
      )
    )
  }

  @Test func asyncWizardReadinessGatesOnlyItsPrimaryAction() {
    #expect(!RentivoAsyncDraftLoadRules.isPrimaryEnabled(hasLoadedBaseline: false))
    #expect(RentivoAsyncDraftLoadRules.isPrimaryEnabled(hasLoadedBaseline: true))
  }
#endif
