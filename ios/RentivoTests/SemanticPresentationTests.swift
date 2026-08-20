import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Suite struct SemanticPresentationTests {
    @Test(
      arguments: [
        (BillStatus.draft, RentivoSemanticTone.neutral, "pencil.circle"),
        (BillStatus.published, RentivoSemanticTone.warning, "megaphone.fill"),
        (BillStatus.sent, RentivoSemanticTone.warning, "paperplane.fill"),
        (BillStatus.paid, RentivoSemanticTone.positive, "checkmark.seal.fill"),
        (
          BillStatus.delayedPayment, RentivoSemanticTone.negative,
          "clock.badge.exclamationmark.fill"
        ),
        (BillStatus.cancelled, RentivoSemanticTone.negative, "xmark.circle.fill"),
      ]
    )
    func everyBillStatusHasTheApprovedToneAndSymbol(
      status: BillStatus, tone: RentivoSemanticTone, symbol: String
    ) {
      let presentation = BillStatusPresentation(status: status)

      #expect(presentation.label == status.label)
      #expect(presentation.tone == tone)
      #expect(presentation.symbol == symbol)
    }

    @Test(
      arguments: [
        (FinancialAmountPresentation.Kind.received, -1, RentivoSemanticTone.neutral),
        (FinancialAmountPresentation.Kind.received, 0, RentivoSemanticTone.neutral),
        (FinancialAmountPresentation.Kind.received, 1, RentivoSemanticTone.positive),
        (FinancialAmountPresentation.Kind.expense, -1, RentivoSemanticTone.neutral),
        (FinancialAmountPresentation.Kind.expense, 0, RentivoSemanticTone.neutral),
        (FinancialAmountPresentation.Kind.expense, 1, RentivoSemanticTone.negative),
        (FinancialAmountPresentation.Kind.result, -1, RentivoSemanticTone.negative),
        (FinancialAmountPresentation.Kind.result, 0, RentivoSemanticTone.neutral),
        (FinancialAmountPresentation.Kind.result, 1, RentivoSemanticTone.positive),
      ]
    )
    func financialToneChangesOnlyAcrossTheApprovedCentavoBoundaries(
      kind: FinancialAmountPresentation.Kind, centavos: Int, tone: RentivoSemanticTone
    ) {
      #expect(
        FinancialAmountPresentation(kind: kind, amount: Money(centavos: centavos)).tone == tone
      )
    }

    @Test(arguments: [
      (-1, RentivoSemanticTone.negative),
      (0, RentivoSemanticTone.neutral),
      (1, RentivoSemanticTone.positive),
    ])
    func homeResultIconUsesTheResultSign(centavos: Int, tone: RentivoSemanticTone) {
      #expect(HomePresentationRules.resultTone(centavos: centavos) == tone)
    }

    @Test func informationAndCurrentUserIdentityStayNeutral() {
      #expect(AppChromeSemanticPresentation.informationTone == .neutral)
      #expect(AppChromeSemanticPresentation.currentUserIdentityTone == .neutral)
    }

    @Test func publishedTimelineMarksOnlyEarlierCanonicalStagesComplete() {
      let timeline = BillTimelinePresentation(currentStatus: .published)

      #expect(timeline.canonicalStages.map(\.status) == [.draft, .published, .sent, .paid])
      #expect(timeline.canonicalStages.map(\.state) == [.completed, .current, .future, .future])
      #expect(timeline.branch == nil)
    }

    @Test func delayedTimelineCompletesThroughSentAndKeepsPaidAsResolution() throws {
      let timeline = BillTimelinePresentation(currentStatus: .delayedPayment)

      #expect(
        timeline.canonicalStages.map(\.state) == [.completed, .completed, .completed, .future]
      )
      let branch = try #require(timeline.branch)
      #expect(branch.status == .delayedPayment)
      #expect(branch.state == .current)
      #expect(
        timeline.accessibilityStages.map(\.status)
          == [.draft, .published, .sent, .paid, .delayedPayment]
      )
    }

    @Test func cancelledTimelineNeverFabricatesACompletedCanonicalStage() throws {
      let timeline = BillTimelinePresentation(currentStatus: .cancelled)

      #expect(timeline.canonicalStages.allSatisfy { $0.state == .future })
      let branch = try #require(timeline.branch)
      #expect(branch.status == .cancelled)
      #expect(branch.state == .current)
    }
  }
#endif
