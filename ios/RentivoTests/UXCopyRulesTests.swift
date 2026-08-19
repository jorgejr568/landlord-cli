import Foundation
import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func communicationComposerBuildsOnlyDecisionBearingSteps() {
    #expect(
      CommunicationComposerRules.steps(availableTypeCount: 1)
        == [.recipients, .message, .review]
    )
    #expect(
      CommunicationComposerRules.steps(availableTypeCount: 2)
        == [.type, .recipients, .message, .review]
    )
    #expect(CommunicationComposerRules.steps(availableTypeCount: 0).isEmpty)
  }

  @Test func variableInsertionReplacesSelectionAndPreservesUTF16Cursor() {
    let token = CommunicationVariable.tenantName.token

    #expect(
      CommunicationVariableInsertion.insert(token, into: "mensagem", selection: NSRange(location: 0, length: 0))
        == ("{{nome_inquilino}}mensagem", NSRange(location: 18, length: 0))
    )
    #expect(
      CommunicationVariableInsertion.insert(token, into: "olá mundo", selection: NSRange(location: 4, length: 5))
        == ("olá {{nome_inquilino}}", NSRange(location: 22, length: 0))
    )
    #expect(
      CommunicationVariableInsertion.insert(token, into: "😀", selection: NSRange(location: 2, length: 0))
        == ("😀{{nome_inquilino}}", NSRange(location: 20, length: 0))
    )
  }

  @Test func previewUsesFirstSelectedRecipientAndEverySupportedValue() {
    let first = BillingRecipient(
      id: RecipientID(rawValue: "first"), name: "Ana", email: "ana@example.com")
    let second = BillingRecipient(
      id: RecipientID(rawValue: "second"), name: "Bruno", email: "bruno@example.com")
    let billing = Billing(
      id: BillingID(rawValue: "billing"),
      name: "Apartamento 101",
      description: "",
      owner: .user(id: 1, name: "Pessoal"),
      items: [],
      recipients: [first, second]
    )
    let bill = Bill(
      id: BillID(rawValue: "bill"),
      billingID: billing.id,
      referenceMonth: ReferenceMonth(year: 2026, month: 8),
      dueDate: nil,
      paidAt: nil,
      notes: "",
      status: .draft,
      lineItems: [
        BillLineItem(
          id: BillLineItemID(rawValue: "line"), description: "Aluguel",
          amount: Money(centavos: 123_456), kind: .fixed)
      ],
      receipts: []
    )

    let context = CommunicationPreviewContext.make(
      billing: billing,
      bill: bill,
      selectedRecipients: [second.id, first.id]
    )

    #expect(context.recipientName == "Ana")
    #expect(context.values[CommunicationVariable.tenantName] == "Ana")
    #expect(context.values[CommunicationVariable.unit] == "Apartamento 101")
    #expect(context.values[CommunicationVariable.referenceMonth] == "agosto de 2026")
    #expect(context.values[CommunicationVariable.dueDate] == "")
    #expect(context.values[CommunicationVariable.total] == "R$ 1.234,56")
    #expect(
      context.personalizationMessage
        == "Prévia para Ana. Cada destinatário receberá a mensagem com seus próprios dados."
    )
  }

  @Test func previewSubstitutesTokensRendersMarkdownAndKeepsHTMLInert() {
    let context = CommunicationPreviewContext(
      recipientName: "Ana",
      values: Dictionary(
        uniqueKeysWithValues: CommunicationVariable.allCases.map { ($0, $0.label) }),
      personalizationMessage: nil
    )
    let subject = CommunicationPreviewRenderer.subject(
      "Olá, {{ nome_inquilino }} — {{unidade}}", context: context)
    let rendered = CommunicationPreviewRenderer.body(
      "**Importante** e _atenção_.\n\n- {{mes}}\n- [Abrir](https://example.com)\n\n<strong>inerte</strong>",
      context: context
    )
    let plainText = String(rendered.characters)

    #expect(subject == "Olá, Nome do inquilino — Unidade")
    #expect(plainText.contains("Importante"))
    #expect(plainText.contains("atenção"))
    #expect(plainText.contains("Mês de referência"))
    #expect(plainText.contains("Abrir"))
    #expect(plainText.contains("<strong>inerte</strong>"))
    #expect(!plainText.contains("**"))
  }

  @Test func draftSaveScopeOnlyChangesWhenTemplateSavingIsEffective() {
    let original = NativeCommunicationDraftState(
      commType: .billReady,
      selectedRecipients: [RecipientID(rawValue: "recipient")],
      subject: "Assunto",
      message: "Mensagem",
      saveScope: nil
    )
    let billingScope = NativeCommunicationDraftState(
      commType: original.commType,
      selectedRecipients: original.selectedRecipients,
      subject: original.subject,
      message: original.message,
      saveScope: .billing
    )
    let ownerScope = NativeCommunicationDraftState(
      commType: original.commType,
      selectedRecipients: original.selectedRecipients,
      subject: original.subject,
      message: original.message,
      saveScope: .owner
    )

    #expect(!original.hasChanges(from: original))
    #expect(billingScope.hasChanges(from: original))
    #expect(ownerScope.hasChanges(from: original))
  }

  @Test func friendlyErrorMapperNeverLeaksServerDetail() {
    let technical = LiveAPIError.server(
      message: "Billing ownership changed /api/v1/billings/550e8400-e29b-41d4-a716-446655440000",
      statusCode: 409,
      code: "billing_transfer_conflict"
    )
    #expect(
      UserFacingError.message(for: technical, operation: .transferBilling)
        == "Não foi possível transferir a cobrança porque os dados mudaram. Atualize e tente novamente."
    )
  }

  @Test func friendlyErrorMapperCoversStatusAndRecoveryCategories() {
    #expect(
      UserFacingError.presentation(
        for: LiveAPIError.server(message: "raw", statusCode: 403, code: nil),
        operation: .saveBilling
      )
        == UserFacingFailure(
          message: "Você não tem permissão para fazer esta alteração. Peça ajuda a um administrador da organização.",
          recovery: .none)
    )
    #expect(
      UserFacingError.presentation(
        for: LiveAPIError.server(message: "raw", statusCode: 404, code: nil),
        operation: .loadBill
      ).message == "Este conteúdo não está mais disponível. Volte e atualize a lista."
    )
    #expect(
      UserFacingError.presentation(
        for: LiveAPIError.server(message: "raw", statusCode: 429, code: nil),
        operation: .sendCommunication
      ).message == "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente."
    )
    #expect(
      UserFacingError.presentation(
        for: LiveAPIError.server(message: "raw", statusCode: 500, code: nil),
        operation: .saveBill
      ).message == "Não foi possível salvar a fatura. Tente novamente em alguns instantes."
    )
    #expect(
      UserFacingError.presentation(for: LiveAPIError.invalidResponse, operation: .loadOrganizations)
        .message
        == "Não foi possível carregar as organizações. Tente novamente em alguns instantes."
    )
    #expect(
      UserFacingError.presentation(
        for: LiveAPIError.server(
          message: "raw", statusCode: 403, code: SecurityViewRules.mfaSetupRequiredCode),
        operation: .saveBilling
      )
        == UserFacingFailure(
          message: "Sua organização exige autenticação em duas etapas. Configure um autenticador para continuar.",
          recovery: .configureAuthenticator)
    )
  }

  @Test func friendlyErrorMapperCoversKnownProblemOverrides() {
    let expected: [(String, UserFacingOperation, String)] = [
      ("pix_setup_required", .saveBill, "Não foi possível gerar a fatura. Configure os dados do PIX da cobrança e tente novamente."),
      ("validation_error", .saveBilling, "Não foi possível salvar a cobrança. Revise os campos e tente novamente."),
      ("invalid_total_amount", .saveBill, "Não foi possível salvar a fatura. Revise os valores dos itens e tente novamente."),
      ("stale_bill_status", .changeBillStatus, "O status da fatura foi alterado. Atualize a página e tente novamente."),
      ("invalid_status_transition", .changeBillStatus, "Essa alteração de status não está mais disponível. Atualize a fatura e escolha outra ação."),
      ("stale_bill_delete", .deleteBill, "Esta fatura já foi excluída. Volte para a cobrança e atualize a lista."),
      ("invoice_not_ready", .openDocument, "O documento ainda está sendo preparado. Aguarde e tente novamente."),
      ("invoice_unavailable", .sendCommunication, "O PDF da fatura ainda não está disponível. Gere o documento e tente novamente."),
      ("recibo_unavailable", .sendCommunication, "O recibo fica disponível depois que a fatura é marcada como paga."),
      ("invalid_recipients", .sendCommunication, "Um destinatário não está mais disponível. Atualize os destinatários da cobrança e tente novamente."),
      ("communication_blocked", .sendCommunication, "A mensagem contém conteúdo que não pode ser enviado. Revise o texto e tente novamente."),
      ("organization_has_billings", .deleteOrganization, "Esta organização ainda possui cobranças. Transfira ou exclua essas cobranças e tente novamente."),
      ("membership_conflict", .updateMember, "Os dados deste membro mudaram. Atualize a organização e tente novamente."),
      ("invite_conflict", .sendInvitation, "Não foi possível enviar o convite. Confira se a pessoa já é membro ou tem um convite pendente."),
    ]

    for (code, operation, message) in expected {
      #expect(
        UserFacingError.message(
          for: LiveAPIError.server(message: "raw", statusCode: 409, code: code),
          operation: operation
        ) == message
      )
    }
  }
#endif
