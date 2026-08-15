package app.rentivo.domain

import java.time.Instant
import java.util.UUID

enum class BillingItemType(val wire: String) {
  FIXED("fixed"),
  VARIABLE("variable"),
  ;

  val label: String get() = if (this == FIXED) "Fixo" else "Variável"

  val showsTemplateAmount: Boolean get() = this == FIXED

  fun normalizedTemplateAmount(centavos: Long): Long = if (this == VARIABLE) 0L else centavos

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

  val isEmpty: Boolean
    get() = key.trim().isEmpty() &&
      merchantName.trim().isEmpty() &&
      merchantCity.trim().isEmpty()
}

data class BillingRecipient(
  val id: RecipientID,
  val name: String,
  val email: String,
)

object EmailAddress {
  private val LOCAL_PATTERN = Regex("""[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+""")
  private val DOMAIN_LABEL_PATTERN = Regex("""[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?""")

  /**
   * Mirrors `ContactInput` at the API boundary so a billing draft accepted here is accepted by
   * the backend as well. Authentication addresses intentionally use a different server contract.
   */
  fun isValid(email: String): Boolean {
    val value = email.trim()
    if (value.length !in 3..320 || value.count { it == '@' } != 1 || value.any { it.isWhitespace() }) {
      return false
    }
    val (local, domain) = value.split('@', limit = 2)
    if (
      local.isEmpty() || local.length > 64 || local.startsWith('.') || local.endsWith('.') ||
      ".." in local || !LOCAL_PATTERN.matches(local) || domain.length > 253
    ) {
      return false
    }
    val labels = domain.split('.')
    return labels.size >= 2 && labels.all(DOMAIN_LABEL_PATTERN::matches)
  }
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
  val pixNeedsSetup: Boolean = false,
  val recipients: List<BillingRecipient> = emptyList(),
  val replyTo: List<BillingRecipient> = emptyList(),
  val communicationTemplates: List<CommunicationTemplate> = emptyList(),
  val capabilities: BillingCapabilities = BillingCapabilities.full,
) {
  val fixedSubtotal: Money
    get() = items.filter { it.type == BillingItemType.FIXED }
      .fold(Money.zero) { total, item -> total + item.amount }

  /** The backend rejects bill creation until the effective PIX configuration is complete. */
  val canGenerateBills: Boolean
    get() = capabilities.canCreateBills && !pixNeedsSetup

  /** Transfer candidates must be user-owned and authorized by the backend capability. */
  val canTransferToOrganization: Boolean
    get() = !owner.isOrganization && capabilities.canTransfer

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
  val replyTo: List<BillingRecipient> = emptyList(),
) {
  fun validate(): List<ValidationIssue> {
    val issues = mutableListOf<ValidationIssue>()
    val normalizedName = name.trim()
    if (normalizedName.isEmpty()) {
      issues.add(ValidationIssue(ValidationField.NAME, "Informe o nome da cobrança."))
    } else if (normalizedName.apiCharacterCount() > 255) {
      issues.add(
        ValidationIssue(ValidationField.NAME, "O nome deve ter no máximo 255 caracteres.")
      )
    }
    if (description.trim().apiCharacterCount() > 2_000) {
      issues.add(
        ValidationIssue(
          ValidationField.DESCRIPTION,
          "A descrição deve ter no máximo 2000 caracteres.",
        )
      )
    }
    if (items.isEmpty()) {
      issues.add(ValidationIssue(ValidationField.ITEMS, "Adicione ao menos um item recorrente."))
    }
    if (items.any { it.description.trim().isEmpty() }) {
      issues.add(ValidationIssue(ValidationField.ITEM_DESCRIPTION, "Descreva todos os itens."))
    } else if (items.any { it.description.trim().apiCharacterCount() > 255 }) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_DESCRIPTION,
          "Descreva todos os itens em até 255 caracteres.",
        )
      )
    }
    if (items.any { it.amount.centavos < 0 }) {
      issues.add(
        ValidationIssue(ValidationField.ITEM_AMOUNT, "Os valores não podem ser negativos.")
      )
    }
    if (!Money.fitsPersistedTotal(
        items.filter { it.type == BillingItemType.FIXED }.map { it.amount.centavos }
      )
    ) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "O valor total deve ser de no máximo R$ 21.474.836,47.",
        )
      )
    }
    if (items.any { it.type == BillingItemType.VARIABLE && it.amount.centavos != 0L }) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "Itens variáveis devem ter valor zero no modelo.",
        )
      )
    }
    if (
      pixOverride != null &&
      (
        pixOverride.merchantName.trim().apiCharacterCount() > 25 ||
          pixOverride.merchantCity.trim().apiCharacterCount() > 15
        )
    ) {
      issues.add(
        ValidationIssue(
          ValidationField.PIX,
          "O recebedor PIX aceita 25 caracteres no nome e 15 na cidade.",
        )
      )
    }
    if (
      recipients.any {
        val recipientName = it.name.trim()
        recipientName.isEmpty() || recipientName.apiCharacterCount() > 255 ||
          !EmailAddress.isValid(it.email.trim())
      }
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
    if (
      replyTo.any {
        val contactName = it.name.trim()
        contactName.isEmpty() || contactName.apiCharacterCount() > 255 ||
          !EmailAddress.isValid(it.email.trim())
      }
    ) {
      issues.add(
        ValidationIssue(
          ValidationField.REPLY_TO,
          "Informe nome e e-mail válidos para todos os contatos de resposta.",
        )
      )
    } else {
      val emails = replyTo.map { it.email.trim().lowercase() }
      if (emails.toSet().size != emails.size) {
        issues.add(
          ValidationIssue(
            ValidationField.REPLY_TO,
            "Remova os contatos de resposta repetidos.",
          )
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
  DESCRIPTION,
  ITEMS,
  ITEM_DESCRIPTION,
  ITEM_AMOUNT,
  PIX,
  RECIPIENT,
  REPLY_TO,
}

private fun String.apiCharacterCount(): Int = codePointCount(0, length)

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
  val mediaType: String = "application/octet-stream",
  val byteCount: Int = 0,
  val createdAt: Instant? = null,
)

data class Attachment(
  val id: AttachmentID,
  val name: String,
  val mediaType: String,
  val byteCount: Int,
)

/** Mirrors the backend `ExportCreateRequest` and its bills-only `ExportService` rows. */
object BillingExportContract {
  val formats: List<String> = listOf("csv", "xlsx")
  val includedSections: List<String> = listOf("Faturas")
}

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
  val canEdit: Boolean = true,
  val canDelete: Boolean = true,
  val canTransition: Boolean = true,
  val canUploadReceipts: Boolean = true,
  val canDeleteReceipts: Boolean = true,
  val canReorderReceipts: Boolean = true,
  val canCompose: Boolean = true,
  val canOpenRecibo: Boolean = false,
) {
  companion object {
    /**
     * Used when no server capabilities are available (older payloads, the mock store). Gating is
     * a server concern; without an answer the client must not invent restrictions of its own.
     */
    val permissive = BillCapabilities(
      canDownloadInvoice = true, canDownloadRecibo = true, canSendInvoice = true,
      canSendRecibo = true, canRegenerate = true, canOpenRecibo = true,
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

data class BillTransition(
  val target: BillStatus,
  val label: String,
  val style: String,
  val requiresConfirmation: Boolean,
) {
  companion object {
    fun fallback(target: BillStatus, current: BillStatus): BillTransition {
      val consequential = target == BillStatus.PAID || target == BillStatus.CANCELLED ||
        (current == BillStatus.PUBLISHED && target == BillStatus.DRAFT) ||
        (current == BillStatus.SENT && target == BillStatus.PUBLISHED) ||
        (current == BillStatus.PAID && target == BillStatus.SENT) ||
        (current == BillStatus.CANCELLED && target == BillStatus.DRAFT)
      val destructive = target == BillStatus.CANCELLED ||
        (current == BillStatus.PUBLISHED && target == BillStatus.DRAFT) ||
        (current == BillStatus.SENT && target == BillStatus.PUBLISHED) ||
        (current == BillStatus.PAID && target == BillStatus.SENT)
      return BillTransition(
        target = target,
        label = "Marcar como ${target.label.lowercase()}",
        style = if (destructive) "danger" else "primary",
        requiresConfirmation = consequential,
      )
    }
  }
}

data class BillCommunication(
  val id: CommunicationID,
  val commType: CommunicationType?,
  val status: String,
  val createdAt: Instant?,
  val sentAt: Instant?,
  val recipientName: String?,
  val recipientEmail: String?,
  val subject: String?,
) {
  val isRedacted: Boolean get() = recipientEmail == null
  val deliveryLabel: String
    get() = when (status) {
      "sent" -> "Enviado"
      "failed" -> "Falhou"
      else -> "Na fila"
    }
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
  val communications: List<BillCommunication> = emptyList(),
  val statusUpdatedAt: Instant? = null,
  val createdAt: Instant? = null,
  /**
   * Server-authoritative transitions for this specific bill, when the API supplies them. `null`
   * means "not provided by this response" — callers fall back to [BillStatus.allowedTransitions]
   * (see [effectiveTransitions]).
   */
  val availableTransitions: List<BillStatus>? = null,
  /** Labels, visual style, and confirmation policy supplied with the transition targets. */
  val availableTransitionActions: List<BillTransition>? = null,
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

  val effectiveTransitionActions: List<BillTransition>
    get() = availableTransitionActions ?: effectiveTransitions.sortedBy { it.wire }.map {
      BillTransition.fallback(target = it, current = status)
    }

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
    statusUpdatedAt = updated.statusUpdatedAt,
    createdAt = updated.createdAt ?: createdAt,
    availableTransitions = updated.availableTransitions,
    availableTransitionActions = updated.availableTransitionActions,
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
    } else if (lineItems.any { it.description.apiCharacterCount() > 255 }) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_DESCRIPTION,
          "Descreva todos os itens da fatura em até 255 caracteres.",
        )
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
    if (!Money.fitsPersistedTotal(lineItems.map { it.amount.centavos })) {
      issues.add(
        ValidationIssue(
          ValidationField.ITEM_AMOUNT,
          "O valor total deve ser de no máximo R$ 21.474.836,47.",
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

object ExpenseInput {
  const val maximumDescriptionLength: Int = 2_000

  fun normalizedDescription(description: String): String = description.trim()

  fun isValidDescription(description: String): Boolean {
    val normalized = normalizedDescription(description)
    return normalized.isNotEmpty() && normalized.apiCharacterCount() <= maximumDescriptionLength
  }
}

object CommunicationContent {
  const val maximumSubjectLength: Int = 998
  const val maximumMessageByteCount: Int = 4_096

  fun normalizedSubject(subject: String): String = subject.trim()

  fun normalizedMessage(message: String): String = message.trim()

  fun validationMessage(subject: String, message: String): String? {
    val normalizedSubject = normalizedSubject(subject)
    val normalizedMessage = normalizedMessage(message)
    return when {
      normalizedSubject.isEmpty() -> "Informe o assunto."
      normalizedSubject.apiCharacterCount() > maximumSubjectLength ->
        "O assunto deve ter no máximo 998 caracteres."
      normalizedMessage.isEmpty() -> "Informe o corpo da mensagem."
      normalizedMessage.toByteArray(Charsets.UTF_8).size > maximumMessageByteCount ->
        "A mensagem deve ter no máximo 4096 bytes."
      else -> null
    }
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
