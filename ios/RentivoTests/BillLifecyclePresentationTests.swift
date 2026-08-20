import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Suite struct BillLifecyclePresentationTests {
    @Test func draftUsesPublishAsPrimaryAndStrengthensCancellation() throws {
      let presentation = makePresentation(
        status: .draft,
        actions: [
          action(.published, "Publicar fatura", style: "secondary"),
          action(.cancelled, "Cancelar fatura", style: "unknown"),
        ]
      )

      #expect(presentation.primaryAction?.action.target == .published)
      let cancellation = try #require(presentation.menuActions.only)
      #expect(cancellation.kind == .destructiveCancellation)
      #expect(cancellation.isDestructive)
      #expect(cancellation.requiresConfirmation)
      #expect(cancellation.confirmationTitle == "Cancelar esta fatura?")
      #expect(
        cancellation.confirmationMessage
          == "A fatura sairá do ciclo de cobrança. Confirme para continuar."
      )
    }

    @Test func publishedGroupsAlternativesRollbacksAndCancellationIndependentlyOfServerOrder() {
      let presentation = makePresentation(
        status: .published,
        actions: [
          action(.cancelled, "Cancelar fatura", style: "primary"),
          action(.draft, "Voltar para rascunho", style: "destructive"),
          action(.sent, "Marcar como enviada", style: "danger"),
          action(.paid, "Marcar como pago", style: "unknown"),
        ]
      )

      #expect(presentation.primaryAction?.action.target == .sent)
      #expect(presentation.menuActions.map(\.action.target) == [.paid, .draft, .cancelled])
      #expect(
        presentation.menuActions.map(\.kind)
          == [.forwardAlternative, .rollback, .destructiveCancellation]
      )
    }

    @Test func sentKeepsDelayedNeutralAndConfirmsRollback() throws {
      let presentation = makePresentation(
        status: .sent,
        actions: [
          action(.paid, "Marcar como pago"),
          action(.delayedPayment, "Marcar pagamento atrasado", style: "danger"),
          action(.published, "Voltar para publicado", style: "primary"),
          action(.cancelled, "Cancelar fatura", style: "secondary"),
        ]
      )

      #expect(presentation.primaryAction?.action.target == .paid)
      #expect(presentation.menuActions.map(\.action.target) == [.delayedPayment, .published, .cancelled])
      let delayed = presentation.menuActions[0]
      #expect(delayed.kind == .forwardAlternative)
      #expect(!delayed.isDestructive)
      let rollback = presentation.menuActions[1]
      #expect(rollback.kind == .rollback)
      #expect(!rollback.isDestructive)
      #expect(rollback.requiresConfirmation)
      #expect(
        rollback.confirmationMessage
          == "O status da fatura voltará para uma etapa anterior. Confirme para continuar."
      )
    }

    @Test func paidRollbackIsNeutralAndConfirmedEvenWhenRawStyleIsDanger() throws {
      let presentation = makePresentation(
        status: .paid,
        actions: [action(.sent, "Reverter pagamento", style: "danger")]
      )

      #expect(presentation.primaryAction == nil)
      let rollback = try #require(presentation.menuActions.only)
      #expect(rollback.kind == .rollback)
      #expect(!rollback.isDestructive)
      #expect(rollback.requiresConfirmation)
    }

    @Test func cancelledRestorationIsNeutralAndConfirmed() throws {
      let presentation = makePresentation(
        status: .cancelled,
        actions: [action(.draft, "Restaurar como rascunho", style: "destructive")]
      )

      #expect(presentation.primaryAction == nil)
      let restoration = try #require(presentation.menuActions.only)
      #expect(restoration.kind == .rollback)
      #expect(!restoration.isDestructive)
      #expect(restoration.requiresConfirmation)
    }

    @Test func delayedPaymentUsesPaidAsPrimary() {
      let presentation = makePresentation(
        status: .delayedPayment,
        actions: [action(.paid, "Marcar como pago")]
      )

      #expect(presentation.primaryAction?.action.target == .paid)
      #expect(presentation.menuActions.isEmpty)
    }

    @Test func anotherForwardActionDoesNotReplaceAMissingNaturalTarget() throws {
      let presentation = makePresentation(
        status: .published,
        actions: [action(.paid, "Marcar como pago")]
      )

      #expect(presentation.primaryAction == nil)
      #expect(try #require(presentation.menuActions.only).action.target == .paid)
    }

    @Test func emptyServerActionsProduceATerminalPresentation() {
      let presentation = makePresentation(status: .draft, actions: [])

      #expect(presentation.primaryAction == nil)
      #expect(presentation.menuActions.isEmpty)
      #expect(presentation.isTerminal)
    }

    @Test(arguments: ["primary", "secondary", "danger", "destructive", "unknown"])
    func rawStyleNeverMakesARollbackDestructive(style: String) throws {
      let presentation = makePresentation(
        status: .paid,
        actions: [action(.sent, "Reverter pagamento", style: style)]
      )

      let rollback = try #require(presentation.menuActions.only)
      #expect(rollback.kind == .rollback)
      #expect(!rollback.isDestructive)
    }

    @Test func serverConfirmationIsPreservedForAnOrdinaryForwardAlternative() throws {
      let presentation = makePresentation(
        status: .published,
        actions: [
          action(.paid, "Marcar como pago", requiresConfirmation: true)
        ]
      )

      let alternative = try #require(presentation.menuActions.only)
      #expect(alternative.kind == .forwardAlternative)
      #expect(alternative.requiresConfirmation)
      #expect(alternative.confirmationMessage == "Confirme a alteração de status desta fatura.")
    }

    private func makePresentation(
      status: BillStatus, actions: [BillTransition]
    ) -> BillLifecyclePresentation {
      BillLifecyclePresentationPolicy.presentation(for: status, actions: actions)
    }

    private func action(
      _ target: BillStatus,
      _ label: String,
      style: String = "secondary",
      requiresConfirmation: Bool = false
    ) -> BillTransition {
      BillTransition(
        target: target,
        label: label,
        style: style,
        requiresConfirmation: requiresConfirmation
      )
    }
  }

  private extension Collection {
    var only: Element? {
      count == 1 ? first : nil
    }
  }
#endif
