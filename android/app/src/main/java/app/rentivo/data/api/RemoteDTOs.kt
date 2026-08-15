package app.rentivo.data.api

import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.ThemeFont
import app.rentivo.domain.ThemeValues
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

// Wire DTOs for the `/api/v1` JSON contract, decoded and encoded by `APIRentivoStore`. They mirror
// the server payloads (snake_case keys, nullable fields) and carry no domain logic; the store owns
// the translation to and from the `domain` models.

/**
 * The single JSON codec for the whole API layer.
 *
 * - `ignoreUnknownKeys`: the server returns more than the app models (transition labels, MFA
 *   blocks, per-billing stats); Swift's `JSONDecoder` skips those by default and so must this.
 * - `explicitNulls = false`: Swift's `JSONEncoder` uses `encodeIfPresent` for optionals, so a
 *   `null` property is *omitted* rather than written as an explicit JSON null. The two bill draft
 *   bodies that genuinely need `due_date: null` on the wire opt out with a hand-written serializer.
 */
internal val apiJson: Json = Json {
  ignoreUnknownKeys = true
  explicitNulls = false
  encodeDefaults = true
}

@Serializable
data class RemoteOrganizationList(val items: List<RemoteOrganization>)

@Serializable
data class RemoteOrganization(
  val uuid: String,
  val name: String,
  @SerialName("current_role") val currentRole: String,
  @SerialName("enforce_mfa") val enforceMFA: Boolean,
  val capabilities: RemoteOrganizationCapabilities,
  val settings: RemoteOrganizationSettings? = null,
  val members: List<RemoteOrganizationMember>? = null,
)

@Serializable
data class RemoteOrganizationCapabilities(
  @SerialName("can_manage") val canManage: Boolean,
  @SerialName("can_invite") val canInvite: Boolean,
  @SerialName("can_create_billing") val canCreateBilling: Boolean,
  @SerialName("can_view_billing_stats") val canViewBillingStats: Boolean,
)

@Serializable
data class RemoteOrganizationSettings(
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
)

@Serializable
data class RemoteOrganizationMember(
  @SerialName("user_id") val userID: Int,
  val email: String,
  val role: String,
  @SerialName("is_current_user") val isCurrentUser: Boolean? = null,
)

@Serializable
data class RemoteOrganizationCreate(
  val name: String,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
) {
  companion object {
    fun from(draft: OrganizationDraft): RemoteOrganizationCreate = RemoteOrganizationCreate(
      name = draft.name,
      pixKey = draft.pix?.key.orEmpty(),
      pixMerchantName = draft.pix?.merchantName.orEmpty(),
      pixMerchantCity = draft.pix?.merchantCity.orEmpty(),
    )
  }
}

@Serializable
data class RemoteOrganizationUpdate(
  val name: String,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
) {
  companion object {
    fun from(draft: OrganizationDraft): RemoteOrganizationUpdate = RemoteOrganizationUpdate(
      name = draft.name,
      pixKey = draft.pix?.key.orEmpty(),
      pixMerchantName = draft.pix?.merchantName.orEmpty(),
      pixMerchantCity = draft.pix?.merchantCity.orEmpty(),
    )
  }
}

@Serializable
data class RemoteMemberRole(val role: String)

@Serializable
data class RemoteInviteCreate(val email: String, val role: String)

@Serializable
data class RemoteMFAPolicy(@SerialName("enforce_mfa") val enforceMFA: Boolean)

@Serializable
data class RemoteMFAPolicyResponse(
  @SerialName("enforce_mfa") val enforceMFA: Boolean,
  @SerialName("mfa_setup_required") val mfaSetupRequired: Boolean,
)

@Serializable
data class RemoteBillingTransfer(@SerialName("organization_uuid") val organizationID: String)

@Serializable
data class RemoteInvitation(
  val uuid: String,
  @SerialName("invited_email") val invitedEmail: String,
  val role: String,
  val status: String,
)

@Serializable
data class RemotePendingInvitationList(val items: List<RemotePendingInvitation>)

@Serializable
data class RemotePendingInvitation(
  val uuid: String,
  @SerialName("organization_uuid") val organizationUUID: String,
  @SerialName("organization_name") val organizationName: String,
  val role: String,
  @SerialName("invited_by_email") val invitedByEmail: String,
  @SerialName("enforce_mfa") val enforceMFA: Boolean,
)

@Serializable
data class RemoteInvitationAcceptance(
  @SerialName("organization_uuid") val organizationUUID: String,
  @SerialName("mfa_setup_required") val mfaSetupRequired: Boolean,
)

@Serializable
data class RemoteSecuritySummary(
  val profile: RemoteProfile,
  val totp: RemoteTOTPStatus,
  val mfa: RemoteMFAStatus,
  val passkeys: List<RemotePasskey>,
)

@Serializable
data class RemoteMFAStatus(
  @SerialName("setup_required") val setupRequired: Boolean,
  @SerialName("organization_enforced") val organizationEnforced: Boolean,
)

@Serializable
data class RemoteTOTPStatus(
  val enabled: Boolean,
  @SerialName("recovery_codes_remaining") val recoveryCodesRemaining: Int,
)

@Serializable
data class RemoteTOTPSetup(
  val secret: String,
  @SerialName("provisioning_uri") val provisioningURI: String,
  @SerialName("qr_code_base64") val qrCodeBase64: String,
)

@Serializable
data class RemoteTOTPConfirm(val code: String)

@Serializable
data class RemoteTOTPDisable(val password: String)

@Serializable
data class RemotePasswordChange(
  @SerialName("current_password") val currentPassword: String,
  @SerialName("new_password") val newPassword: String,
  @SerialName("confirm_password") val confirmPassword: String,
)

@Serializable
data class RemoteDeleteAccount(val password: String)

@Serializable
data class RemoteAccountDeletionReadiness(
  @SerialName("can_delete") val canDelete: Boolean,
  val reason: String? = null,
)

@Serializable
data class RemotePasskey(
  val uuid: String,
  val name: String,
  @SerialName("created_at") val createdAt: String,
  @SerialName("last_used_at") val lastUsedAt: String? = null,
)

@Serializable
data class RemoteRecoveryCodes(@SerialName("recovery_codes") val recoveryCodes: List<String>)

@Serializable
data class RemoteContactInput(val name: String, val email: String) {
  companion object {
    fun from(recipient: BillingRecipient): RemoteContactInput =
      RemoteContactInput(name = recipient.name, email = recipient.email)
  }
}

@Serializable
data class RemoteCommunicationPreviewRequest(val subject: String, val body: String)

@Serializable
data class RemoteCommunicationPreview(
  val html: String,
  val severe: List<String>,
  val mild: List<String>,
)

@Serializable
data class RemoteCommunicationSendRequest(
  @SerialName("bill_uuid") val billID: String,
  @SerialName("comm_type") val commType: String,
  val subject: String,
  val body: String,
  @SerialName("recipient_uuids") val recipientIDs: List<String>,
  @SerialName("acknowledge_warning") val acknowledgeWarning: Boolean,
  @SerialName("save_scope") val saveScope: String?,
)

@Serializable
data class RemoteCommunicationSend(@SerialName("queued_count") val queuedCount: Int)

@Serializable
data class RemoteExportRequest(val format: String)

@Serializable
data class RemoteExport(val format: String, val status: String)

@Serializable
data class RemoteReceiptUpload(val items: List<RemoteReceipt>)

@Serializable
data class RemoteReceiptList(val items: List<RemoteReceipt>)

@Serializable
data class RemoteReceiptOrder(val order: List<String>)

@Serializable
data class RemoteReceipt(
  val uuid: String,
  val filename: String,
  @SerialName("content_type") val contentType: String,
  @SerialName("file_size") val fileSize: Int,
  @SerialName("sort_order") val sortOrder: Int,
  @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class RemoteAttachmentList(val items: List<RemoteAttachment>)

@Serializable
data class RemoteAttachment(
  val uuid: String,
  val name: String,
  @SerialName("content_type") val contentType: String,
  @SerialName("file_size") val fileSize: Int,
)

@Serializable
data class RemoteAPIKeyList(val items: List<RemoteAPIKey>)

@Serializable
data class RemoteAPIKeyOptions(
  val scopes: List<String>,
  @SerialName("personal_workspace") val personalWorkspace: RemoteAPIKeyPersonalWorkspace,
  val organizations: List<RemoteAPIKeyOrganizationWorkspace>,
  @SerialName("default_expiration_days") val defaultExpirationDays: Int,
  @SerialName("max_expiration_days") val maxExpirationDays: Int,
)

@Serializable
data class RemoteAPIKeyPersonalWorkspace(
  @SerialName("resource_type") val resourceType: String,
  @SerialName("resource_id") val resourceID: String,
)

@Serializable
data class RemoteAPIKeyOrganizationWorkspace(
  @SerialName("resource_type") val resourceType: String,
  @SerialName("resource_id") val resourceID: String,
  val name: String,
)

@Serializable
data class RemoteAPIKey(
  val uuid: String,
  val name: String,
  val hint: String,
  val scopes: List<String>,
  val grants: List<RemoteAPIKeyGrant>,
  @SerialName("expires_at") val expiresAt: String,
  @SerialName("created_at") val createdAt: String,
  @SerialName("last_used_at") val lastUsedAt: String? = null,
  @SerialName("revoked_at") val revokedAt: String? = null,
)

/**
 * `POST /api/v1/api-keys` answers with the one-time secret *alongside* the created key's own
 * fields, flattened into the same object rather than nested — so both are decoded from it.
 */
@Serializable(with = RemoteCreatedAPIKeySerializer::class)
data class RemoteCreatedAPIKey(val secret: String, val apiKey: RemoteAPIKey)

internal object RemoteCreatedAPIKeySerializer : KSerializer<RemoteCreatedAPIKey> {
  override val descriptor: SerialDescriptor = buildClassSerialDescriptor("RemoteCreatedAPIKey")

  override fun deserialize(decoder: Decoder): RemoteCreatedAPIKey {
    val input = decoder as? JsonDecoder
      ?: throw SerializationException("RemoteCreatedAPIKey requires a JSON decoder")
    val element = input.decodeJsonElement() as? JsonObject
      ?: throw SerializationException("RemoteCreatedAPIKey expects a JSON object")
    val secret = (element["secret"] as? JsonPrimitive)?.contentOrNull
      ?: throw SerializationException("Missing api key secret")
    return RemoteCreatedAPIKey(
      secret = secret,
      apiKey = input.json.decodeFromJsonElement(RemoteAPIKey.serializer(), element),
    )
  }

  override fun serialize(encoder: Encoder, value: RemoteCreatedAPIKey): Unit =
    throw SerializationException("RemoteCreatedAPIKey is decode-only")
}

@Serializable
data class RemoteAPIKeyGrant(
  @SerialName("resource_type") val resourceType: String,
  @SerialName("resource_id") val resourceID: String? = null,
  val available: Boolean,
)

@Serializable
data class RemoteAPIKeyCreate(
  val name: String,
  val scopes: List<String>,
  val grants: List<RemoteAPIKeyGrantInput>,
  @SerialName("expires_at") val expiresAt: String,
) {
  companion object {
    fun from(draft: APIKeyDraft): RemoteAPIKeyCreate = RemoteAPIKeyCreate(
      name = draft.name,
      scopes = draft.scopes.map { it.wire }.sorted(),
      grants = draft.grants.map { RemoteAPIKeyGrantInput.from(it) },
      expiresAt = WireInstant.iso8601(draft.expiresAt),
    )
  }
}

@Serializable
data class RemoteAPIKeyUpdate(
  val name: String,
  val scopes: List<String>? = null,
  val grants: List<RemoteAPIKeyGrantInput>? = null,
) {
  companion object {
    fun from(draft: APIKeyDraft, updateGrants: Boolean): RemoteAPIKeyUpdate = RemoteAPIKeyUpdate(
      name = draft.name,
      scopes = if (draft.shouldUpdateScopes) draft.scopes.map { it.wire }.sorted() else null,
      grants = if (updateGrants && draft.shouldUpdateGrants) {
        draft.grants.map { RemoteAPIKeyGrantInput.from(it) }
      } else null,
    )
  }
}

@Serializable
data class RemoteAPIKeyGrantInput(
  @SerialName("resource_type") val resourceType: String,
  @SerialName("resource_id") val resourceID: String,
) {
  companion object {
    fun from(grant: APIKeyGrant): RemoteAPIKeyGrantInput = RemoteAPIKeyGrantInput(
      resourceType = grant.resourceType.wire,
      resourceID = grant.resourceID.rawValue,
    )
  }
}

/** The internet-date-time rendering the API key contract expects for `expires_at`. */
internal object WireInstant {
  private val FORMATTER: DateTimeFormatter =
    DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

  fun iso8601(instant: Instant): String = FORMATTER.format(instant)
}

@Serializable
data class RemoteTheme(
  @SerialName("owner_name") val ownerName: String,
  @SerialName("effective_source") val effectiveSource: String,
  val stored: RemoteThemeValues? = null,
  val effective: RemoteThemeValues,
  val capabilities: RemoteThemeCapabilities,
)

@Serializable
data class RemoteThemeCapabilities(
  @SerialName("can_edit") val canEdit: Boolean,
  @SerialName("can_reset") val canReset: Boolean,
)

@Serializable
data class RemoteThemeValues(
  @SerialName("header_font") val headerFont: String,
  @SerialName("text_font") val textFont: String,
  val primary: String,
  @SerialName("primary_light") val primaryLight: String,
  val secondary: String,
  @SerialName("secondary_dark") val secondaryDark: String,
  @SerialName("text_color") val textColor: String,
  @SerialName("text_contrast") val textContrast: String,
) {
  companion object {
    fun from(values: ThemeValues): RemoteThemeValues = RemoteThemeValues(
      headerFont = values.headerFont.wire,
      textFont = values.textFont.wire,
      primary = values.primary,
      primaryLight = values.primaryLight,
      secondary = values.secondary,
      secondaryDark = values.secondaryDark,
      textColor = values.textColor,
      textContrast = values.textContrast,
    )
  }
}

/** Unknown font names fall back rather than failing the whole theme decode. */
internal fun RemoteThemeValues.toDomain(): ThemeValues = ThemeValues(
  headerFont = ThemeFont.fromWire(headerFont) ?: ThemeFont.MONTSERRAT,
  textFont = ThemeFont.fromWire(textFont) ?: ThemeFont.OPEN_SANS,
  primary = primary,
  primaryLight = primaryLight,
  secondary = secondary,
  secondaryDark = secondaryDark,
  textColor = textColor,
  textContrast = textContrast,
)

@Serializable
data class RemoteBillingDraft(
  val name: String,
  val description: String,
  val owner: RemoteOwnerInput,
  val items: List<RemoteBillingItemInput>,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
  val recipients: List<RemoteContactInput>,
  @SerialName("reply_to") val replyTo: List<RemoteContactInput>,
) {
  companion object {
    fun from(draft: BillingDraft): RemoteBillingDraft = RemoteBillingDraft(
      name = draft.name,
      description = draft.description,
      owner = when (val owner = draft.owner) {
        is BillingOwner.User -> RemoteOwnerInput(type = "user", uuid = null)
        is BillingOwner.Organization ->
          RemoteOwnerInput(type = "organization", uuid = owner.id.rawValue)
      },
      items = draft.items.map { RemoteBillingItemInput.from(it) },
      pixKey = draft.pixOverride?.key.orEmpty(),
      pixMerchantName = draft.pixOverride?.merchantName.orEmpty(),
      pixMerchantCity = draft.pixOverride?.merchantCity.orEmpty(),
      recipients = draft.recipients.map { RemoteContactInput.from(it) },
      replyTo = draft.replyTo.map { RemoteContactInput.from(it) },
    )
  }
}

@Serializable
data class RemoteBillingUpdate(
  val name: String,
  val description: String,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
  val items: List<RemoteBillingItemInput>,
  val recipients: List<RemoteContactInput>,
  @SerialName("reply_to") val replyTo: List<RemoteContactInput>,
) {
  companion object {
    fun from(draft: BillingDraft): RemoteBillingUpdate = RemoteBillingUpdate(
      name = draft.name,
      description = draft.description,
      pixKey = draft.pixOverride?.key.orEmpty(),
      pixMerchantName = draft.pixOverride?.merchantName.orEmpty(),
      pixMerchantCity = draft.pixOverride?.merchantCity.orEmpty(),
      items = draft.items.map { RemoteBillingItemInput.from(it) },
      recipients = draft.recipients.map { RemoteContactInput.from(it) },
      replyTo = draft.replyTo.map { RemoteContactInput.from(it) },
    )
  }
}

@Serializable
data class RemoteOwnerInput(val type: String, val uuid: String?)

// Billing items minted client-side (a new row added in the form) carry a 36-char UUID as their id;
// the server only accepts a 26-char Crockford-base32 ULID (or null) for `uuid`, so only ids that
// already look like a server-issued ULID may be sent through — everything else must be null so the
// server mints its own.
private val ULID_ALLOWED_CHARACTERS = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toSet()

internal fun isULID(value: String): Boolean =
  value.length == 26 && value.all(ULID_ALLOWED_CHARACTERS::contains)

@Serializable
data class RemoteBillingItemInput(
  val uuid: String?,
  val description: String,
  val amount: Long,
  @SerialName("item_type") val itemType: String,
) {
  companion object {
    fun from(item: BillingItem): RemoteBillingItemInput = RemoteBillingItemInput(
      uuid = item.id.rawValue.takeIf { isULID(it) },
      description = item.description,
      amount = item.amount.centavos,
      itemType = item.type.wire,
    )
  }
}

@Serializable(with = RemoteBillCreateDraftSerializer::class)
data class RemoteBillCreateDraft(
  val referenceMonth: String,
  val dueDate: String?,
  val notes: String,
  val extras: List<RemoteBillExtra>,
  val variableAmounts: Map<String, Long>,
) {
  companion object {
    fun from(draft: BillDraft): RemoteBillCreateDraft = RemoteBillCreateDraft(
      referenceMonth = draft.referenceMonth.apiValue,
      dueDate = draft.dueDate?.iso8601,
      notes = draft.notes,
      extras = draft.lineItems
        .filter { it.kind == BillLineItemKind.EXTRA }
        .map { RemoteBillExtra.from(it) },
      // The server requires the variable_amounts key set to exactly match the billing's own
      // variable BillingItem uuids, so only line items whose id is already a real ULID (i.e. one
      // sourced from the billing's items, not a freshly client-minted id) can be included.
      variableAmounts = draft.lineItems
        .filter { it.kind == BillLineItemKind.VARIABLE && isULID(it.id.rawValue) }
        .associate { it.id.rawValue to it.amount.centavos },
    )
  }
}

/**
 * Hand-written so a `null` [RemoteBillCreateDraft.dueDate] reaches the server as an explicit JSON
 * null instead of being dropped from the body — see [RemoteBillUpdateDraftSerializer] for why that
 * distinction matters. Every stored property must have a line here; this encoder is not kept in
 * sync automatically.
 */
internal object RemoteBillCreateDraftSerializer : KSerializer<RemoteBillCreateDraft> {
  override val descriptor: SerialDescriptor = buildClassSerialDescriptor("RemoteBillCreateDraft")

  override fun serialize(encoder: Encoder, value: RemoteBillCreateDraft) {
    val output = encoder as? JsonEncoder
      ?: throw SerializationException("RemoteBillCreateDraft requires a JSON encoder")
    output.encodeJsonElement(
      buildJsonObject {
        put("reference_month", value.referenceMonth)
        put("due_date", value.dueDate)
        put("notes", value.notes)
        putJsonArray("extras") {
          for (extra in value.extras) {
            add(
              buildJsonObject {
                put("description", extra.description)
                put("amount", extra.amount)
              }
            )
          }
        }
        putJsonObject("variable_amounts") {
          for ((uuid, amount) in value.variableAmounts) put(uuid, amount)
        }
      }
    )
  }

  override fun deserialize(decoder: Decoder): RemoteBillCreateDraft =
    throw SerializationException("RemoteBillCreateDraft is encode-only")
}

@Serializable
data class RemoteBillExtra(val description: String, val amount: Long) {
  companion object {
    fun from(item: BillLineItem): RemoteBillExtra =
      RemoteBillExtra(description = item.description, amount = item.amount.centavos)
  }
}

@Serializable(with = RemoteBillUpdateDraftSerializer::class)
data class RemoteBillUpdateDraft(
  val dueDate: String?,
  val notes: String,
  val lineItems: List<RemoteBillLineItemInput>,
) {
  companion object {
    fun from(draft: BillDraft): RemoteBillUpdateDraft = RemoteBillUpdateDraft(
      dueDate = draft.dueDate?.iso8601,
      notes = draft.notes,
      lineItems = draft.lineItems.map { RemoteBillLineItemInput.from(it) },
    )
  }
}

/**
 * The server's PATCH handler treats an *absent* `due_date` as "leave unchanged" and an explicit
 * `null` as "clear it". Omitting a null optional would make clearing a due date impossible, so the
 * key is always written.
 */
internal object RemoteBillUpdateDraftSerializer : KSerializer<RemoteBillUpdateDraft> {
  override val descriptor: SerialDescriptor = buildClassSerialDescriptor("RemoteBillUpdateDraft")

  override fun serialize(encoder: Encoder, value: RemoteBillUpdateDraft) {
    val output = encoder as? JsonEncoder
      ?: throw SerializationException("RemoteBillUpdateDraft requires a JSON encoder")
    output.encodeJsonElement(
      buildJsonObject {
        put("due_date", value.dueDate)
        put("notes", value.notes)
        putJsonArray("line_items") {
          for (item in value.lineItems) {
            add(
              buildJsonObject {
                put("description", item.description)
                put("amount", item.amount)
                put("item_type", item.itemType)
              }
            )
          }
        }
      }
    )
  }

  override fun deserialize(decoder: Decoder): RemoteBillUpdateDraft =
    throw SerializationException("RemoteBillUpdateDraft is encode-only")
}

@Serializable
data class RemoteBillLineItemInput(
  val description: String,
  val amount: Long,
  @SerialName("item_type") val itemType: String,
) {
  companion object {
    fun from(item: BillLineItem): RemoteBillLineItemInput = RemoteBillLineItemInput(
      description = item.description,
      amount = item.amount.centavos,
      itemType = item.kind.wire,
    )
  }
}

@Serializable
data class RemoteBillTransition(
  val target: String,
  @SerialName("current_status") val currentStatus: String,
)

@Serializable
data class RemoteExpenseCreate(
  val description: String,
  val category: String,
  @SerialName("incurred_on") val incurredOn: String,
  val amount: Long,
)

@Serializable
data class RemoteBillingList(
  val items: List<RemoteBillingListItem>,
  val stats: RemoteBillingStats,
)

@Serializable
data class RemoteBillingStats(
  val received: Long,
  val pending: Long,
  val overdue: Long,
  @SerialName("total_expenses") val totalExpenses: Long,
  @SerialName("net_income") val netIncome: Long,
  @SerialName("paid_count") val paidCount: Int,
  @SerialName("billed_count") val billedCount: Int,
)

@Serializable
data class RemoteProfile(
  val email: String,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
)

@Serializable
data class RemotePixUpdate(
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
) {
  companion object {
    fun from(pix: PixConfiguration?): RemotePixUpdate = RemotePixUpdate(
      pixKey = pix?.key.orEmpty(),
      pixMerchantName = pix?.merchantName.orEmpty(),
      pixMerchantCity = pix?.merchantCity.orEmpty(),
    )
  }
}

@Serializable
data class RemotePixUpdateResponse(val profile: RemoteProfile)

@Serializable
data class RemoteBillingListItem(
  val uuid: String,
  val name: String,
  val description: String,
  val owner: RemoteOwner,
  val capabilities: RemoteBillingCapabilities,
)

@Serializable
data class RemoteBilling(
  val uuid: String,
  val name: String,
  val description: String,
  val owner: RemoteOwner,
  val items: List<RemoteBillingItem>,
  @SerialName("pix_key") val pixKey: String,
  @SerialName("pix_merchant_name") val pixMerchantName: String,
  @SerialName("pix_merchant_city") val pixMerchantCity: String,
  @SerialName("pix_needs_setup") val pixNeedsSetup: Boolean? = null,
  val recipients: List<RemoteBillingContact>,
  @SerialName("reply_to") val replyTo: List<RemoteBillingContact>,
  // Optional so a payload without the field keeps decoding; the live billing detail contract
  // always includes it.
  @SerialName("communication_templates")
  val communicationTemplates: List<RemoteCommunicationTemplate>? = null,
  val capabilities: RemoteBillingCapabilities,
)

@Serializable
data class RemoteBillingContact(
  val uuid: String,
  val name: String? = null,
  val email: String? = null,
)

@Serializable
data class RemoteCommunicationTemplate(
  @SerialName("comm_type") val commType: String,
  val subject: String,
  val body: String,
)

@Serializable
data class RemoteBillingCapabilities(
  @SerialName("can_edit") val canEdit: Boolean,
  @SerialName("can_read_bills") val canReadBills: Boolean,
  @SerialName("can_create_bills") val canCreateBills: Boolean,
  @SerialName("can_manage_bills") val canManageBills: Boolean,
  @SerialName("can_read_expenses") val canReadExpenses: Boolean,
  @SerialName("can_write_expenses") val canWriteExpenses: Boolean,
  @SerialName("can_create_exports") val canCreateExports: Boolean,
  @SerialName("can_read_attachments") val canReadAttachments: Boolean,
  @SerialName("can_write_attachments") val canWriteAttachments: Boolean,
  @SerialName("can_read_theme") val canReadTheme: Boolean,
  @SerialName("can_manage_theme") val canManageTheme: Boolean,
  @SerialName("can_upload_bill_receipts") val canUploadBillReceipts: Boolean,
  @SerialName("can_delete") val canDelete: Boolean,
  @SerialName("can_transfer") val canTransfer: Boolean,
)

@Serializable
data class RemoteOwner(
  val type: String,
  val uuid: String? = null,
  val name: String? = null,
)

@Serializable
data class RemoteBillingItem(
  val uuid: String,
  val description: String,
  val amount: Long,
  @SerialName("item_type") val itemType: String,
)

@Serializable
data class RemoteBillList(val items: List<RemoteBill>)

@Serializable
data class RemoteBill(
  val uuid: String,
  @SerialName("reference_month") val referenceMonth: String,
  val notes: String,
  val status: String,
  @SerialName("due_date") val dueDate: String? = null,
  @SerialName("status_updated_at") val statusUpdatedAt: String? = null,
  @SerialName("created_at") val createdAt: String? = null,
  @SerialName("line_items") val lineItems: List<RemoteBillLine>,
  val receipts: List<RemoteReceipt>? = null,
  val communications: List<RemoteBillCommunication>? = null,
  @SerialName("total_amount") val totalAmount: Long,
  @SerialName("available_transitions") val availableTransitions: List<RemoteAvailableTransition>,
  @SerialName("pdf_render_status") val pdfRenderStatus: String? = null,
  @SerialName("has_invoice") val hasInvoice: Boolean? = null,
  @SerialName("has_recibo") val hasRecibo: Boolean? = null,
  val capabilities: RemoteBillCapabilities? = null,
)

@Serializable
data class RemoteBillCommunication(
  val uuid: String,
  @SerialName("comm_type") val commType: String,
  val status: String,
  @SerialName("created_at") val createdAt: String? = null,
  @SerialName("sent_at") val sentAt: String? = null,
  @SerialName("recipient_name") val recipientName: String? = null,
  @SerialName("recipient_email") val recipientEmail: String? = null,
  val subject: String? = null,
)

@Serializable
data class RemoteBillCapabilities(
  @SerialName("can_download_invoice") val canDownloadInvoice: Boolean,
  @SerialName("can_download_recibo") val canDownloadRecibo: Boolean,
  @SerialName("can_send_invoice") val canSendInvoice: Boolean,
  @SerialName("can_send_recibo") val canSendRecibo: Boolean,
  @SerialName("can_regenerate") val canRegenerate: Boolean,
  @SerialName("can_edit") val canEdit: Boolean,
  @SerialName("can_delete") val canDelete: Boolean,
  @SerialName("can_transition") val canTransition: Boolean,
  @SerialName("can_upload_receipts") val canUploadReceipts: Boolean,
  @SerialName("can_delete_receipts") val canDeleteReceipts: Boolean,
  @SerialName("can_reorder_receipts") val canReorderReceipts: Boolean,
  @SerialName("can_compose") val canCompose: Boolean,
  @SerialName("can_open_recibo") val canOpenRecibo: Boolean? = null,
)

@Serializable
data class RemoteAvailableTransition(
  val target: String,
  val label: String,
  val style: String,
  @SerialName("requires_confirmation") val requiresConfirmation: Boolean,
)

@Serializable
data class RemoteBillLine(
  val description: String,
  val amount: Long,
  @SerialName("item_type") val itemType: String,
)

@Serializable
data class RemoteExpenseList(val items: List<RemoteExpense>)

@Serializable
data class RemoteExpense(
  val uuid: String,
  val description: String,
  val category: String,
  @SerialName("incurred_on") val incurredOn: String,
  val amount: Long,
)

@Serializable
data class RemoteProblem(val detail: String? = null)
