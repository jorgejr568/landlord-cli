package app.rentivo.domain

import java.time.Instant
import java.util.UUID

enum class BillingItemType(val wire: String) {
  FIXED("fixed"),
  VARIABLE("variable"),
  ;

  val label: String get() = if (this == FIXED) "Fixo" else "Variável"

  val showsTemplateAmount: Boolean get() = this == FIXED

  fun normalizedTemplateAmount(centavos: Int): Int = if (this == VARIABLE) 0 else centavos

  companion object {
    fun fromWire(wire: String?): BillingItemType? = entries.firstOrNull { it.wire == wire }
  }
}

data class BillingItem(
  val id: BillingItemID,
  val description: String,
  val amount: Money,
  val type: BillingItemType,
  val sortOrder: Int,
) {
  companion object {
    /** Convenience for locally created rows, which the server has not assigned an id to yet. */
    fun generated(
      description: String,
      amount: Money,
      type: BillingItemType,
      sortOrder: Int,
      id: UUID = UUID.randomUUID(),
    ): BillingItem = BillingItem(
      id = BillingItemID(rawValue = id.toString()),
      description = description,
      amount = amount,
      type = type,
      sortOrder = sortOrder,
    )
  }
}

sealed class BillingOwner {
  abstract val name: String

  data class User(val id: Int, override val name: String) : BillingOwner()

  data class Organization(val id: OrganizationID, override val name: String) : BillingOwner()

  val workspaceID: WorkspaceID
    get() = when (this) {
      is User -> WorkspaceID.personal
      is Organization -> WorkspaceID(rawValue = id.rawValue)
    }

  val isOrganization: Boolean get() = this is Organization
}

data class PixConfiguration(
  val key: String,
  val merchantName: String,
  val merchantCity: String,
) {
  val isComplete: Boolean
    get() = key.trim().isNotEmpty() &&
      merchantName.trim().isNotEmpty() &&
      merchantCity.trim().isNotEmpty()
}

data class BillingRecipient(
  val id: RecipientID,
  val name: String,
  val email: String,
)

object EmailAddress {
  // A pragmatic wire-boundary check (not full RFC 5322 validation): rejects obviously malformed
  // addresses (missing "@", missing domain dot, embedded whitespace) before they ever reach the
  // API, without blocking legitimate addresses on edge-case grammar the server itself accepts.
  private val PATTERN = Regex("""^[^\s@]+@[^\s@]+\.[^\s@]+$""")

  fun isValid(email: String): Boolean = PATTERN.matches(email)
}

data class BillingCapabilities(
  val canEdit: Boolean,
  val canReadBills: Boolean,
  val canCreateBills: Boolean,
  val canManageBills: Boolean,
  val canReadExpenses: Boolean,
  val canWriteExpenses: Boolean,
  val canCreateExports: Boolean,
  val canReadAttachments: Boolean,
  val canWriteAttachments: Boolean,
  val canReadTheme: Boolean,
  val canManageTheme: Boolean,
  val canUploadBillReceipts: Boolean,
  val canDelete: Boolean,
  val canTransfer: Boolean,
) {
  val allowsEveryAction: Boolean
    get() = listOf(
      canEdit, canReadBills, canCreateBills, canManageBills, canReadExpenses,
      canWriteExpenses, canCreateExports, canReadAttachments, canWriteAttachments,
      canReadTheme, canManageTheme, canUploadBillReceipts, canDelete, canTransfer,
    ).all { it }

  companion object {
    val full = BillingCapabilities(
      canEdit = true, canReadBills = true, canCreateBills = true, canManageBills = true,
      canReadExpenses = true, canWriteExpenses = true, canCreateExports = true,
      canReadAttachments = true, canWriteAttachments = true, canReadTheme = true,
      canManageTheme = true, canUploadBillReceipts = true, canDelete = true, canTransfer = true,
    )

    val viewer = BillingCapabilities(
      canEdit = false, canReadBills = true, canCreateBills = false, canManageBills = false,
      canReadExpenses = true, canWriteExpenses = false, canCreateExports = false,
      canReadAttachments = true, canWriteAttachments = false, canReadTheme = true,
      canManageTheme = false, canUploadBillReceipts = false, canDelete = false,
      canTransfer = false,
    )
  }
}

data class Billing(
  val id: BillingID,
  val name: String,
  val description: String,
  val owner: BillingOwner,
  val items: List<BillingItem>,
  val pixOverride: PixConfiguration? = null,
  val recipients: List<BillingRecipient> = emptyList(),
  val replyTo: String? = null,
  val communicationTemplates: List<CommunicationTemplate> = emptyList(),
  val capabilities: BillingCapabilities = BillingCapabilities.full,
) {
  val fixedSubtotal: Money
    get() = items.filter { it.type == BillingItemType.FIXED }
      .fold(Money.zero) { total, item -> total + item.amount }

  fun template(type: CommunicationType): CommunicationTemplate? =
    communicationTemplates.firstOrNull { it.commType == type }
}

data class BillingDraft(
  val name: String,
  val description: String,
  val owner: BillingOwner,
  val items: List<BillingItem>,
  val pixOverride: PixConfiguration? = null,
  val recipients: List<BillingRecipient> = emptyList(),
  val replyTo: String? = null,
) {
  fun validate(): List<ValidationIssue> {
    val issues = mutableListOf<ValidationIssue>()
    if (name.trim().isEmpty()) {
      issues.add(ValidationIssue(ValidationField.NAME, "Informe o nome da cobrança."))
    }
    if (items.isEmpty()) {
      issues.add(ValidationIssue(ValidationField.ITEMS, "Adicione ao menos um item recorrente."))
    }
    if (items.any { it.description.trim().isEmpty() }) {
      issues.add(ValidationIssue(ValidationField.ITEM_DESCRIPTION, "Descreva todos os itens."))
    }
    if (items.any { it.amount.centavos < 0 }) {
      issues.add(
        ValidationIssue(ValidationField.ITEM_AMOUNT, "Os valores não podem ser negativos.")
      )
    }
    if (items.any { it.type == BillingItemType.VARIABLE && it.amount.centavos != 0 }) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "Itens variáveis devem ter valor zero no modelo.",
        )
      )
    }
    if (
      recipients.any { it.name.trim().isEmpty() || !EmailAddress.isValid(it.email.trim()) }
    ) {
      issues.add(
        ValidationIssue(
          ValidationField.RECIPIENT,
          "Informe nome e e-mail válidos para todos os destinatários.",
        )
      )
    } else {
      // The send endpoint requires distinct recipient uuids and the server keys contacts by
      // email, so duplicates here would break the communication flow later.
      val emails = recipients.map { it.email.trim().lowercase() }
      if (emails.toSet().size != emails.size) {
        issues.add(
          ValidationIssue(ValidationField.RECIPIENT, "Remova os destinatários repetidos.")
        )
      }
    }
    return issues
  }

  companion object {
    val empty = BillingDraft(
      name = "",
      description = "",
      owner = BillingOwner.User(id = StableID.userAna, name = "Pessoal"),
      items = emptyList(),
    )
  }
}

enum class ValidationField {
  NAME,
  ITEMS,
  ITEM_DESCRIPTION,
  ITEM_AMOUNT,
  RECIPIENT,
}

data class ValidationIssue(
  val field: ValidationField,
  val message: String,
)

enum class BillLineItemKind(val wire: String) {
  FIXED("fixed"),
  VARIABLE("variable"),
  EXTRA("extra"),
  ;

  companion object {
    fun fromWire(wire: String?): BillLineItemKind? = entries.firstOrNull { it.wire == wire }
  }
}

data class BillLineItem(
  val id: BillLineItemID,
  val description: String,
  val amount: Money,
  val kind: BillLineItemKind,
) {
  companion object {
    /** Convenience for locally created rows, which the server has not assigned an id to yet. */
    fun generated(
      description: String,
      amount: Money,
      kind: BillLineItemKind,
      id: UUID = UUID.randomUUID(),
    ): BillLineItem = BillLineItem(
      id = BillLineItemID(rawValue = id.toString()),
      description = description,
      amount = amount,
      kind = kind,
    )
  }
}

enum class BillStatus(val wire: String) {
  DRAFT("draft"),
  PUBLISHED("published"),
  SENT("sent"),
  PAID("paid"),
  CANCELLED("cancelled"),
  DELAYED_PAYMENT("delayed_payment"),
  ;

  val allowedTransitions: Set<BillStatus>
    get() = when (this) {
      DRAFT -> setOf(PUBLISHED, CANCELLED)
      PUBLISHED -> setOf(SENT, PAID, CANCELLED)
      SENT -> setOf(PAID, DELAYED_PAYMENT, CANCELLED)
      DELAYED_PAYMENT -> setOf(PAID, CANCELLED)
      PAID, CANCELLED -> emptySet()
    }

  fun canTransition(target: BillStatus): Boolean = allowedTransitions.contains(target)

  val label: String
    get() = when (this) {
      DRAFT -> "Rascunho"
      PUBLISHED -> "Publicada"
      SENT -> "Enviada"
      PAID -> "Paga"
      CANCELLED -> "Cancelada"
      DELAYED_PAYMENT -> "Pagamento atrasado"
    }

  companion object {
    fun fromWire(wire: String?): BillStatus? = entries.firstOrNull { it.wire == wire }
  }
}

data class Receipt(
  val id: ReceiptID,
  val name: String,
  val sortOrder: Int,
)

data class Attachment(
  val id: AttachmentID,
  val name: String,
  val mediaType: String,
  val byteCount: Int,
)

/**
 * The server's asynchronous PDF render state for a bill. The wire literals are exactly
 * `"pending" | "succeeded" | "failed"`; anything else (including `null`) decodes to `null`.
 */
enum class PDFRenderStatus(val wire: String) {
  PENDING("pending"),
  SUCCEEDED("succeeded"),
  FAILED("failed"),
  ;

  companion object {
    fun fromWire(wire: String?): PDFRenderStatus? = entries.firstOrNull { it.wire == wire }
  }
}

/**
 * Server-authoritative, per-bill action gates. The server folds the pending render state into
 * these flags, so the UI can treat them as the single source of truth for what is allowed now.
 */
data class BillCapabilities(
  val canDownloadInvoice: Boolean,
  val canDownloadRecibo: Boolean,
  val canSendInvoice: Boolean,
  val canSendRecibo: Boolean,
  val canRegenerate: Boolean,
) {
  companion object {
    /**
     * Used when no server capabilities are available (older payloads, the mock store). Gating is
     * a server concern; without an answer the client must not invent restrictions of its own.
     */
    val permissive = BillCapabilities(
      canDownloadInvoice = true, canDownloadRecibo = true, canSendInvoice = true,
      canSendRecibo = true, canRegenerate = true,
    )
  }
}

/** Poll cadence for a bill whose PDF is still rendering. */
object BillPDFPolling {
  const val INTERVAL_MILLIS: Long = 3_000L

  /**
   * Poll only while the loaded bill reports a pending render; stop on success, failure, an
   * unknown status, or no bill at all.
   */
  fun shouldPoll(bill: Bill?): Boolean = bill?.isRenderingPDF == true
}

data class Bill(
  val id: BillID,
  val billingID: BillingID,
  val referenceMonth: ReferenceMonth,
  /**
   * `null` when the server has no due date for this bill (`due_date: null` on the wire) —
   * distinct from a date, and never a sentinel.
   */
  val dueDate: DateOnly?,
  val paidAt: DateOnly?,
  val notes: String,
  val status: BillStatus,
  val lineItems: List<BillLineItem>,
  val receipts: List<Receipt>,
  /**
   * Server-authoritative transitions for this specific bill, when the API supplies them. `null`
   * means "not provided by this response" — callers fall back to [BillStatus.allowedTransitions]
   * (see [effectiveTransitions]).
   */
  val availableTransitions: List<BillStatus>? = null,
  /**
   * Server-authoritative total for this bill, when the API supplies it. `null` means "not
   * provided by this response" — callers fall back to the computed [total] (see [effectiveTotal]).
   */
  val serverTotal: Money? = null,
  /**
   * `null` means the bill was never rendered, or the server reported a status this client does
   * not model — either way, not "rendering".
   */
  val pdfRenderStatus: PDFRenderStatus? = null,
  val hasInvoice: Boolean = false,
  val hasRecibo: Boolean = false,
  val capabilities: BillCapabilities = BillCapabilities.permissive,
) {
  /**
   * The PDF for this bill is being (re)generated in the background, so any document already on
   * the server may be stale and must not be opened or e-mailed yet.
   */
  val isRenderingPDF: Boolean get() = pdfRenderStatus == PDFRenderStatus.PENDING

  val total: Money
    get() = lineItems.fold(Money.zero) { running, item -> running + item.amount }

  /** The computed total, unless the server supplied an authoritative one for this bill. */
  val effectiveTotal: Money get() = serverTotal ?: total

  /**
   * The local state-machine rules ([BillStatus.allowedTransitions]), unless the server supplied
   * authoritative transitions for this specific bill.
   */
  val effectiveTransitions: Set<BillStatus>
    get() = availableTransitions?.toSet() ?: status.allowedTransitions

  fun canTransition(target: BillStatus): Boolean = effectiveTransitions.contains(target)

  /**
   * Folds a freshly returned *bill summary* into this loaded bill: render state, action gates and
   * status come from [updated], while detail-only data (receipts, line items) stays as loaded.
   * `POST .../regenerate` answers with the summary shape, which carries no receipts at all, so
   * replacing the loaded bill with it would empty the receipt list until the next poll tick.
   */
  fun applyingRenderMetadata(updated: Bill): Bill = copy(
    pdfRenderStatus = updated.pdfRenderStatus,
    capabilities = updated.capabilities,
    hasInvoice = updated.hasInvoice,
    hasRecibo = updated.hasRecibo,
    status = updated.status,
    availableTransitions = updated.availableTransitions,
  )
}

data class BillDraft(
  val billingID: BillingID,
  val referenceMonth: ReferenceMonth,
  val dueDate: DateOnly?,
  val notes: String,
  val lineItems: List<BillLineItem>,
) {
  val total: Money
    get() = lineItems.fold(Money.zero) { running, item -> running + item.amount }

  fun validate(): List<ValidationIssue> {
    val issues = mutableListOf<ValidationIssue>()
    if (lineItems.isEmpty()) {
      issues.add(ValidationIssue(ValidationField.ITEMS, "Adicione ao menos um item."))
    }
    if (lineItems.any { it.description.trim().isEmpty() }) {
      issues.add(
        ValidationIssue(ValidationField.ITEM_DESCRIPTION, "Descreva todos os itens da fatura.")
      )
    }
    if (lineItems.any { it.kind != BillLineItemKind.EXTRA && it.amount.centavos < 0 }) {
      issues.add(
        ValidationIssue(ValidationField.ITEM_AMOUNT, "Os valores não podem ser negativos.")
      )
    }
    // The server requires `BillExtraRequest.amount` to be strictly positive
    // (`exclusiveMinimum: 0`): a zero or negative extra always 422s.
    if (lineItems.any { it.kind == BillLineItemKind.EXTRA && it.amount.centavos <= 0 }) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "Os itens extras devem ter valor maior que zero.",
        )
      )
    }
    return issues
  }
}

enum class ExpenseCategory(val wire: String) {
  PROPERTY_TAX("iptu"),
  CONDOMINIUM("condominio"),
  MAINTENANCE("manutencao"),
  INSURANCE("seguro"),
  OTHER("outros"),
  ;

  val label: String
    get() = when (this) {
      PROPERTY_TAX -> "IPTU"
      CONDOMINIUM -> "Condomínio"
      MAINTENANCE -> "Manutenção"
      INSURANCE -> "Seguro"
      OTHER -> "Outros"
    }

  companion object {
    fun fromWire(wire: String?): ExpenseCategory? = entries.firstOrNull { it.wire == wire }
  }
}

data class Expense(
  val id: ExpenseID,
  val billingID: BillingID,
  val description: String,
  val amount: Money,
  val category: ExpenseCategory,
  val incurredOn: DateOnly,
)

enum class CommunicationType(val wire: String) {
  BILL_READY("bill_ready"),
  PAYMENT_RECEIPT("payment_receipt"),
  ;

  val label: String
    get() = when (this) {
      BILL_READY -> "Fatura"
      PAYMENT_RECEIPT -> "Recibo de pagamento"
    }

  companion object {
    fun fromWire(wire: String?): CommunicationType? = entries.firstOrNull { it.wire == wire }
  }
}

enum class CommunicationSaveScope(val wire: String) {
  BILLING("billing"),
  OWNER("owner"),
  ;

  companion object {
    fun fromWire(wire: String?): CommunicationSaveScope? = entries.firstOrNull { it.wire == wire }
  }
}

data class CommunicationTemplate(
  val commType: CommunicationType,
  val subject: String,
  val body: String,
)

data class CommunicationRecord(
  val id: CommunicationID,
  val billingID: BillingID,
  val billID: BillID?,
  val recipients: List<String>,
  val subject: String,
  val message: String,
  val sentAt: Instant,
)

data class CommunicationPreview(
  val html: String,
  val severeWarnings: List<String>,
  val mildWarnings: List<String>,
  val id: UUID = UUID.randomUUID(),
)
