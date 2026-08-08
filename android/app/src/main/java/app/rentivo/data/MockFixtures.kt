package app.rentivo.data

import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.ActivityKind
import app.rentivo.domain.Attachment
import app.rentivo.domain.AttachmentID
import app.rentivo.domain.Bill
import app.rentivo.domain.BillCapabilities
import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemID
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.CommunicationTemplate
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.ExpenseID
import app.rentivo.domain.Expense
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.Invitation
import app.rentivo.domain.InvitationStatus
import app.rentivo.domain.Money
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationMember
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.Passkey
import app.rentivo.domain.PasskeyID
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.RecentActivity
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ReferenceMonth
import app.rentivo.domain.SecuritySummary
import app.rentivo.domain.StableID
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import app.rentivo.domain.UserProfile
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** The seed data the in-memory demo store starts from and resets back to. */
data class MockFixtures(val snapshot: StoreSnapshot) {

  companion object {
    /**
     * Templates every demo billing carries, shortened stand-ins for the system defaults in
     * `backend/rentivo/communications/defaults.py`. The server resolves a template for every
     * communication type (billing, then owner, then system default), so no real billing ever
     * reaches the composer without one; demo billings must behave the same.
     */
    val defaultCommunicationTemplates: List<CommunicationTemplate> = listOf(
      CommunicationTemplate(
        commType = CommunicationType.BILL_READY,
        subject = "Cobrança {{unidade}} — {{mes}}",
        body = """
          Prezado {{nome_inquilino}},

          Segue em anexo a cobrança de **{{mes}}** da unidade **{{unidade}}**.

          Atenciosamente.
        """.trimIndent(),
      ),
      CommunicationTemplate(
        commType = CommunicationType.PAYMENT_RECEIPT,
        subject = "Recibo de pagamento {{unidade}} — {{mes}}",
        body = """
          Prezado {{nome_inquilino}},

          Confirmamos o recebimento de **{{total}}** referente a **{{mes}}**. Segue o recibo em anexo.

          Atenciosamente.
        """.trimIndent(),
      ),
    )

    // Declared after the templates it seeds every billing with: companion properties initialize
    // top to bottom, so the reverse order would build the fixtures against a null template list.
    val canonical: MockFixtures = MockFixtures(snapshot = canonicalSnapshot())

    private fun canonicalSnapshot(): StoreSnapshot {
      val personalPix = PixConfiguration(
        key = "ana@example.com",
        merchantName = "ANA SILVA",
        merchantCity = "SAO PAULO",
      )
      val organizationPix = PixConfiguration(
        key = "12345678000190",
        merchantName = "IMOB HORIZONTE",
        merchantCity = "SAO PAULO",
      )
      val profile = UserProfile(id = StableID.userAna, email = "ana@example.com", pix = personalPix)
      val personalOwner = BillingOwner.User(id = profile.id, name = "Pessoal")
      val organizationOwner = BillingOwner.Organization(
        id = StableID.organizationHorizonte,
        name = "Imobiliária Horizonte",
      )

      val billings = listOf(
        billing(
          id = StableID.billingAurora101,
          name = "Apt 101 - Edifício Aurora",
          description = "Apartamento 2 quartos, bloco A",
          owner = personalOwner,
          items = listOf(
            ItemSpec("Aluguel", 180_000, BillingItemType.FIXED),
            ItemSpec("Condomínio", 65_000, BillingItemType.FIXED),
            ItemSpec("IPTU", 28_000, BillingItemType.FIXED),
            ItemSpec("Água", 0, BillingItemType.VARIABLE),
            ItemSpec("Luz", 0, BillingItemType.VARIABLE),
          ),
        ),
        billing(
          id = StableID.billingAurora202,
          name = "Apt 202 - Edifício Aurora",
          description = "Apartamento 3 quartos, bloco B",
          owner = personalOwner,
          items = listOf(
            ItemSpec("Aluguel", 250_000, BillingItemType.FIXED),
            ItemSpec("Condomínio", 65_000, BillingItemType.FIXED),
            ItemSpec("IPTU", 35_000, BillingItemType.FIXED),
            ItemSpec("Água", 0, BillingItemType.VARIABLE),
            ItemSpec("Luz", 0, BillingItemType.VARIABLE),
            ItemSpec("Gás", 0, BillingItemType.VARIABLE),
          ),
        ),
        billing(
          id = StableID.billingSolNascente303,
          name = "Apt 303 - Residencial Sol Nascente",
          description = "Studio mobiliado",
          owner = personalOwner,
          items = listOf(
            ItemSpec("Aluguel", 120_000, BillingItemType.FIXED),
            ItemSpec("Condomínio", 45_000, BillingItemType.FIXED),
            ItemSpec("Internet", 10_000, BillingItemType.FIXED),
            ItemSpec("Água", 0, BillingItemType.VARIABLE),
          ),
        ),
        billing(
          id = StableID.billingVilaFlores1,
          name = "Casa 1 - Vila das Flores",
          description = "Casa 3 quartos com quintal",
          owner = organizationOwner,
          items = listOf(
            ItemSpec("Aluguel", 320_000, BillingItemType.FIXED),
            ItemSpec("IPTU", 42_000, BillingItemType.FIXED),
            ItemSpec("Água", 0, BillingItemType.VARIABLE),
            ItemSpec("Luz", 0, BillingItemType.VARIABLE),
          ),
        ),
        billing(
          id = StableID.billingTorreNorte501,
          name = "Apt 501 - Torre Norte",
          description = "Cobertura duplex",
          owner = organizationOwner,
          items = listOf(
            ItemSpec("Aluguel", 450_000, BillingItemType.FIXED),
            ItemSpec("Condomínio", 120_000, BillingItemType.FIXED),
            ItemSpec("IPTU", 58_000, BillingItemType.FIXED),
            ItemSpec("Água", 0, BillingItemType.VARIABLE),
          ),
        ),
        billing(
          id = StableID.billingCentro12,
          name = "Sala 12 - Centro Empresarial",
          description = "Sala comercial 40 m²",
          owner = organizationOwner,
          items = listOf(
            ItemSpec("Aluguel", 200_000, BillingItemType.FIXED),
            ItemSpec("Condomínio", 35_000, BillingItemType.FIXED),
            ItemSpec("IPTU", 18_000, BillingItemType.FIXED),
            ItemSpec("Luz", 0, BillingItemType.VARIABLE),
          ),
        ),
      )

      val paidReceipt = Receipt(
        id = ReceiptID(rawValue = stableID(2_001)),
        name = "comprovante-pix-junho.pdf",
        sortOrder = 0,
      )
      val paidReceiptImage = Receipt(
        id = ReceiptID(rawValue = stableID(2_002)),
        name = "confirmacao-bancaria.jpg",
        sortOrder = 1,
      )
      val bills = listOf(
        bill(
          id = StableID.billDraft,
          billingID = StableID.billingAurora101,
          month = 7,
          status = BillStatus.DRAFT,
          variableAmount = 12_300,
        ),
        bill(
          id = StableID.billPublished,
          billingID = StableID.billingAurora101,
          month = 8,
          status = BillStatus.PUBLISHED,
          variableAmount = 11_100,
        ),
        bill(
          id = StableID.billSent,
          billingID = StableID.billingAurora202,
          month = 7,
          status = BillStatus.SENT,
          variableAmount = 18_500,
        ),
        bill(
          id = StableID.billPaid,
          billingID = StableID.billingAurora101,
          month = 6,
          status = BillStatus.PAID,
          variableAmount = 14_340,
          paidAt = DateOnly(year = 2026, month = 6, day = 8),
          receipts = listOf(paidReceipt, paidReceiptImage),
        ),
        bill(
          id = StableID.billCancelled,
          billingID = StableID.billingSolNascente303,
          month = 6,
          status = BillStatus.CANCELLED,
          variableAmount = 8_700,
        ),
        bill(
          id = StableID.billDelayed,
          billingID = StableID.billingVilaFlores1,
          month = 6,
          status = BillStatus.DELAYED_PAYMENT,
          variableAmount = 16_000,
        ),
      )

      val expenses = listOf(
        Expense(
          id = ExpenseID(rawValue = stableID(5_001)),
          billingID = StableID.billingAurora101,
          description = "Manutenção do interfone",
          amount = Money(centavos = 25_000),
          category = ExpenseCategory.MAINTENANCE,
          incurredOn = DateOnly(year = 2026, month = 5, day = 18),
        ),
        Expense(
          id = ExpenseID(rawValue = stableID(5_002)),
          billingID = StableID.billingVilaFlores1,
          description = "Seguro residencial",
          amount = Money(centavos = 18_000),
          category = ExpenseCategory.INSURANCE,
          incurredOn = DateOnly(year = 2026, month = 4, day = 10),
        ),
      )

      val anaMember = OrganizationMember(
        userID = profile.id,
        email = profile.email,
        role = OrganizationRole.ADMIN,
      )
      val organizations = listOf(
        Organization(
          id = StableID.organizationHorizonte,
          name = "Imobiliária Horizonte",
          pix = organizationPix,
          members = listOf(
            anaMember,
            OrganizationMember(
              userID = 11,
              email = "bruno@example.com",
              role = OrganizationRole.ADMIN,
            ),
            OrganizationMember(
              userID = 12,
              email = "carla@example.com",
              role = OrganizationRole.MANAGER,
            ),
            OrganizationMember(
              userID = 13,
              email = "diego@example.com",
              role = OrganizationRole.VIEWER,
            ),
          ),
          requiresMFA = true,
          currentUserRole = OrganizationRole.ADMIN,
        ),
        Organization(
          id = OrganizationID(rawValue = stableID(20)),
          name = "Condomínio Aurora",
          pix = null,
          members = listOf(
            OrganizationMember(
              userID = 21,
              email = "sindico@aurora.com",
              role = OrganizationRole.ADMIN,
            )
          ),
          requiresMFA = false,
          currentUserRole = OrganizationRole.VIEWER,
        ),
      )

      val now = Instant.ofEpochSecond(1_768_521_600L)
      val integrationKey = APIKeyMetadata(
        id = StableID.apiKeyDashboard,
        name = "Painel financeiro",
        hint = "rntv-v1-abcd••yz",
        scopes = setOf(
          APIKeyScope.PROFILE_READ,
          APIKeyScope.BILLINGS_READ,
          APIKeyScope.EXPENSES_READ,
        ),
        grants = listOf(
          APIKeyGrant(
            resourceType = WorkspaceResourceType.USER,
            resourceID = WorkspaceID.personal,
          )
        ),
        expiresAt = Instant.ofEpochSecond(1_798_761_600L),
        lastUsedAt = now,
        createdAt = Instant.ofEpochSecond(1_752_796_800L),
        revokedAt = null,
      )

      return StoreSnapshot(
        profile = profile,
        billings = billings,
        bills = bills,
        expenses = expenses,
        attachments = mapOf(
          StableID.billingAurora101 to listOf(
            Attachment(
              id = AttachmentID(rawValue = stableID(6_001)),
              name = "contrato-locacao.pdf",
              mediaType = "application/pdf",
              byteCount = 184_320,
            )
          )
        ),
        organizations = organizations,
        invitations = listOf(
          Invitation(
            id = StableID.invitationHorizonte,
            organizationID = OrganizationID(rawValue = stableID(20)),
            organizationName = "Condomínio Aurora",
            email = profile.email,
            role = OrganizationRole.MANAGER,
            status = InvitationStatus.PENDING,
          )
        ),
        communications = emptyList(),
        security = SecuritySummary(
          totpEnabled = true,
          recoveryCodeCount = 6,
          passkeys = listOf(
            Passkey(
              id = PasskeyID(rawValue = stableID(7_001)),
              name = "Notebook pessoal",
              createdAt = Instant.ofEpochSecond(1_736_640_000L),
              lastUsedAt = now,
            )
          ),
        ),
        apiKeys = listOf(integrationKey),
        themes = mapOf(
          ThemeTarget.User to ThemeValues.rentivo,
          ThemeTarget.Organization(StableID.organizationHorizonte) to ThemeValues.rentivo,
          ThemeTarget.Billing(StableID.billingTorreNorte501) to ThemeValues.sunset,
        ),
        activities = listOf(
          RecentActivity(
            id = UUID.fromString("00000000-0000-0000-0000-000000008001"),
            kind = ActivityKind.BILL,
            title = "Fatura paga",
            detail = "Apt 101 - Edifício Aurora · junho de 2026",
            occurredAt = now,
          )
        ),
      )
    }

    private data class ItemSpec(
      val description: String,
      val centavos: Int,
      val type: BillingItemType,
    )

    private fun billing(
      id: BillingID,
      name: String,
      description: String,
      owner: BillingOwner,
      items: List<ItemSpec>,
    ): Billing = Billing(
      id = id,
      name = name,
      description = description,
      owner = owner,
      items = items.mapIndexed { index, item ->
        BillingItem(
          id = BillingItemID(rawValue = stableID(10_000 + index)),
          description = item.description,
          amount = Money(centavos = item.centavos),
          type = item.type,
          sortOrder = index,
        )
      },
      recipients = listOf(
        BillingRecipient(
          id = RecipientID(rawValue = stableID(20_000)),
          name = "Locatário",
          email = "locatario@example.com",
        ),
        BillingRecipient(
          id = RecipientID(rawValue = stableID(20_001)),
          name = "Fiadora",
          email = "fiadora@example.com",
        ),
      ),
      replyTo = "ana@example.com",
      communicationTemplates = defaultCommunicationTemplates,
    )

    private fun bill(
      id: BillID,
      billingID: BillingID,
      month: Int,
      status: BillStatus,
      variableAmount: Int,
      paidAt: DateOnly? = null,
      receipts: List<Receipt> = emptyList(),
    ): Bill {
      val fixedAmount = when (billingID) {
        StableID.billingAurora101 -> 273_000
        StableID.billingAurora202 -> 350_000
        StableID.billingSolNascente303 -> 175_000
        StableID.billingVilaFlores1 -> 362_000
        StableID.billingTorreNorte501 -> 628_000
        else -> 253_000
      }
      return Bill(
        id = id,
        billingID = billingID,
        referenceMonth = ReferenceMonth(year = 2026, month = month),
        dueDate = DateOnly(year = 2026, month = month, day = 10),
        paidAt = paidAt,
        notes = if (status == BillStatus.DELAYED_PAYMENT) "Pagamento em acompanhamento." else "",
        status = status,
        lineItems = listOf(
          BillLineItem(
            id = BillLineItemID(rawValue = stableID(30_000)),
            description = "Itens fixos",
            amount = Money(centavos = fixedAmount),
            kind = BillLineItemKind.FIXED,
          ),
          BillLineItem(
            id = BillLineItemID(rawValue = stableID(31_000)),
            description = "Consumo variável",
            amount = Money(centavos = variableAmount),
            kind = BillLineItemKind.VARIABLE,
          ),
        ),
        receipts = receipts,
        pdfRenderStatus = PDFRenderStatus.SUCCEEDED,
        hasInvoice = true,
        // The recibo only exists once the bill has been paid.
        hasRecibo = status == BillStatus.PAID,
        capabilities = BillCapabilities.permissive,
      )
    }

    /**
     * The UUID-shaped raw value fixtures use for stable identifiers. Swift mints these through a
     * generic `ResourceID<Tag>`; Kotlin's identifiers are separate value classes, so the helper
     * answers the raw string and each call site wraps it in the identifier it needs.
     */
    private fun stableID(value: Int): String =
      "00000000-0000-0000-0000-" + String.format(Locale.ROOT, "%012d", value)
  }
}
