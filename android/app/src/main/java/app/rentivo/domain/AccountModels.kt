package app.rentivo.domain

import java.time.Instant

/**
 * Mirrors the server's role contract exactly (`admin`, `manager`, `viewer`). There is no "owner"
 * role on the wire: `OrganizationMemberUpdateRequest.role` and every invite/member response enum
 * accept only these three values, so no case here may be excluded from mutation paths or role
 * pickers.
 */
enum class OrganizationRole(val wire: String) {
  ADMIN("admin"),
  MANAGER("manager"),
  VIEWER("viewer"),
  ;

  val label: String
    get() = when (this) {
      ADMIN -> "Administrador"
      MANAGER -> "Gerente"
      VIEWER -> "Visualizador"
    }

  companion object {
    fun fromWire(wire: String?): OrganizationRole? = entries.firstOrNull { it.wire == wire }
  }
}

data class OrganizationCapabilities(
  val canManage: Boolean,
  val canInvite: Boolean,
  val canCreateBilling: Boolean,
  val canViewBillingStats: Boolean,
) {
  companion object {
    val full = OrganizationCapabilities(
      canManage = true, canInvite = true, canCreateBilling = true, canViewBillingStats = true,
    )

    val manager = OrganizationCapabilities(
      canManage = false, canInvite = false, canCreateBilling = true, canViewBillingStats = true,
    )

    val viewer = OrganizationCapabilities(
      canManage = false, canInvite = false, canCreateBilling = false, canViewBillingStats = true,
    )

    fun forRole(role: OrganizationRole): OrganizationCapabilities = when (role) {
      OrganizationRole.ADMIN -> full
      OrganizationRole.MANAGER -> manager
      OrganizationRole.VIEWER -> viewer
    }
  }
}

data class OrganizationMember(
  val userID: Int,
  val email: String,
  val role: OrganizationRole,
  val isCurrentUser: Boolean = false,
) {
  val id: Int get() = userID
}

data class Organization(
  val id: OrganizationID,
  val name: String,
  val pix: PixConfiguration?,
  val members: List<OrganizationMember>,
  val requiresMFA: Boolean,
  val currentUserRole: OrganizationRole,
  val capabilities: OrganizationCapabilities = OrganizationCapabilities.full,
) {
  /** Roles are descriptive; the capability returned by the API is authoritative. */
  val billingOwnerForCreation: BillingOwner?
    get() = if (capabilities.canCreateBilling) {
      BillingOwner.Organization(id = id, name = name)
    } else {
      null
    }
}

/**
 * Effective policy returned after changing an organization's MFA requirement. The setup flag is
 * user-specific: it is true when the current administrator still has no enrolled MFA method.
 */
data class OrganizationMFAPolicy(
  val enforceMFA: Boolean,
  val mfaSetupRequired: Boolean,
)

data class OrganizationDraft(
  val name: String,
  val pix: PixConfiguration?,
) {
  val isValid: Boolean
    get() = nameValidationMessage(name) == null && pix?.let {
      pixValidationMessage(
        key = it.key,
        merchantName = it.merchantName,
        city = it.merchantCity,
      ) == null
    } != false

  companion object {
    const val nameLimit: Int = 255

    fun nameValidationMessage(name: String): String? {
      val normalized = name.trim()
      return when {
        normalized.isEmpty() -> "Informe o nome da organização."
        normalized.codePointCount(0, normalized.length) > nameLimit ->
          "O nome da organização deve ter até 255 caracteres."
        else -> null
      }
    }

    fun pixValidationMessage(key: String, merchantName: String, city: String): String? {
      val normalizedKey = key.trim()
      val normalizedName = merchantName.trim()
      val normalizedCity = city.trim()
      return when {
        normalizedKey.isEmpty() -> null
        normalizedName.isEmpty() || normalizedCity.isEmpty() ->
          "Informe o nome e a cidade do recebedor para usar uma chave PIX."
        normalizedName.codePointCount(0, normalizedName.length) > 25 ->
          "O nome do recebedor deve ter até 25 caracteres."
        normalizedCity.codePointCount(0, normalizedCity.length) > 15 ->
          "A cidade do recebedor deve ter até 15 caracteres."
        else -> null
      }
    }
  }
}

/**
 * Mirrors the deliberately permissive `OrganizationInviteCreateRequest` address contract. This
 * must stay separate from the stricter billing-contact validator because invites accept `a@b`.
 */
object OrganizationInviteEmail {
  const val maximumLength: Int = 320

  fun normalized(email: String): String = email.trim().lowercase()

  fun validationMessage(email: String): String? {
    val value = normalized(email)
    return when {
      value.isEmpty() -> "Informe o e-mail."
      value.codePointCount(0, value.length) > maximumLength ->
        "O e-mail deve ter até 320 caracteres."
      value.count { it == '@' } != 1 || value.any { it.isWhitespace() } ->
        "Informe um e-mail válido."
      value.substringBefore('@').isEmpty() || value.substringAfter('@').isEmpty() ->
        "Informe um e-mail válido."
      else -> null
    }
  }

  fun isValid(email: String): Boolean = validationMessage(email) == null
}

enum class InvitationStatus(val wire: String) {
  PENDING("pending"),
  ACCEPTED("accepted"),
  DECLINED("declined"),
  ;

  companion object {
    fun fromWire(wire: String?): InvitationStatus? = entries.firstOrNull { it.wire == wire }
  }
}

data class Invitation(
  val id: InvitationID,
  val organizationID: OrganizationID,
  val organizationName: String,
  val email: String,
  val role: OrganizationRole,
  val status: InvitationStatus,
  val invitedByEmail: String? = null,
  val organizationEnforcesMFA: Boolean = false,
)

data class InvitationAcceptance(
  val organizationID: OrganizationID,
  val mfaSetupRequired: Boolean,
)

data class Passkey(
  val id: PasskeyID,
  val name: String,
  val createdAt: Instant,
  val lastUsedAt: Instant?,
)

data class SecuritySummary(
  val totpEnabled: Boolean,
  val recoveryCodeCount: Int,
  val passkeys: List<Passkey>,
  val setupRequired: Boolean = false,
  val organizationEnforced: Boolean = false,
)

data class TOTPEnrollment(
  val secret: String,
  val provisioningURI: String,
  val qrCodeBase64: String,
)

enum class APIKeyScope(val wire: String) {
  PROFILE_READ("profile:read"),
  ACCOUNT_WRITE("account:write"),
  SECURITY_MANAGE("security:manage"),
  API_KEYS_MANAGE("api_keys:manage"),
  ORGANIZATIONS_READ("organizations:read"),
  ORGANIZATIONS_WRITE("organizations:write"),
  ORGANIZATIONS_MEMBERS("organizations:members"),
  BILLINGS_READ("billings:read"),
  BILLINGS_WRITE("billings:write"),
  BILLS_READ("bills:read"),
  BILLS_WRITE("bills:write"),
  EXPENSES_READ("expenses:read"),
  EXPENSES_WRITE("expenses:write"),
  FILES_READ("files:read"),
  FILES_WRITE("files:write"),
  COMMUNICATIONS_READ("communications:read"),
  COMMUNICATIONS_SEND("communications:send"),
  THEMES_READ("themes:read"),
  THEMES_WRITE("themes:write"),
  EXPORTS_CREATE("exports:create"),
  ;

  companion object {
    /** The scopes an integration key may request — privileged account operations are excluded. */
    val integrationCases: List<APIKeyScope> = listOf(
      PROFILE_READ, ORGANIZATIONS_READ, BILLINGS_READ, BILLINGS_WRITE, BILLS_READ,
      BILLS_WRITE, EXPENSES_READ, EXPENSES_WRITE, FILES_READ, FILES_WRITE,
      COMMUNICATIONS_READ, COMMUNICATIONS_SEND, THEMES_READ, THEMES_WRITE, EXPORTS_CREATE,
    )

    fun fromWire(wire: String?): APIKeyScope? = entries.firstOrNull { it.wire == wire }
  }
}

enum class WorkspaceResourceType(val wire: String) {
  USER("user"),
  ORGANIZATION("organization"),
  ;

  companion object {
    fun fromWire(wire: String?): WorkspaceResourceType? = entries.firstOrNull { it.wire == wire }
  }
}

data class APIKeyWorkspaceOption(
  val resourceType: WorkspaceResourceType,
  val resourceID: WorkspaceID,
  val name: String,
) {
  val id: WorkspaceID get() = resourceID
}

data class APIKeyOptions(
  val scopes: List<APIKeyScope>,
  val personalWorkspace: APIKeyWorkspaceOption,
  val organizations: List<APIKeyWorkspaceOption>,
  val defaultExpirationDays: Int,
  val maxExpirationDays: Int,
) {
  fun defaultExpiration(now: Instant = Instant.now()): Instant =
    now.plusSeconds(defaultExpirationDays * 86_400L)

  /** One-minute request-latency buffer, matching the web client's upper-bound clamp. */
  fun maximumExpiration(now: Instant = Instant.now()): Instant =
    now.plusSeconds(maxExpirationDays * 86_400L - 60)

  fun clampedExpiration(selected: Instant, now: Instant = Instant.now()): Instant =
    maxOf(minOf(selected, maximumExpiration(now)), now.plusSeconds(60))
}

object APIKeyValidation {
  fun isValidName(name: String): Boolean = name.trim().let {
    it.isNotEmpty() && it.codePointCount(0, it.length) <= 255
  }
}

data class APIKeyGrant(
  val resourceType: WorkspaceResourceType,
  val resourceID: WorkspaceID,
  val available: Boolean = true,
)

data class APIKeyMetadata(
  val id: APIKeyID,
  val name: String,
  val hint: String,
  val scopes: Set<APIKeyScope>,
  val grants: List<APIKeyGrant>,
  val expiresAt: Instant,
  val lastUsedAt: Instant?,
  val createdAt: Instant,
  val revokedAt: Instant?,
)

data class APIKeyDraft(
  val name: String,
  val scopes: Set<APIKeyScope>,
  val grants: List<APIKeyGrant>,
  val expiresAt: Instant,
) {
  companion object {
    val demo = APIKeyDraft(
      name = "Painel financeiro",
      scopes = setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ),
      grants = listOf(
        APIKeyGrant(
          resourceType = WorkspaceResourceType.USER,
          resourceID = WorkspaceID.personal,
        )
      ),
      expiresAt = Instant.ofEpochSecond(1_798_761_600L),
    )
  }
}

data class CreatedAPIKeySecret(
  val metadata: APIKeyMetadata,
  val secret: String,
)

enum class ThemeFont(val wire: String) {
  MONTSERRAT("Montserrat"),
  ROBOTO("Roboto"),
  LORA("Lora"),
  PLAYFAIR_DISPLAY("Playfair Display"),
  OPEN_SANS("Open Sans"),
  SOURCE_SANS_3("Source Sans 3"),
  MERRIWEATHER("Merriweather"),
  RALEWAY("Raleway"),
  OSWALD("Oswald"),
  NUNITO("Nunito"),
  ;

  companion object {
    fun fromWire(wire: String?): ThemeFont? = entries.firstOrNull { it.wire == wire }
  }
}

data class ThemeValues(
  val headerFont: ThemeFont,
  val textFont: ThemeFont,
  val primary: String,
  val primaryLight: String,
  val secondary: String,
  val secondaryDark: String,
  val textColor: String,
  val textContrast: String,
) {
  companion object {
    val rentivo = ThemeValues(
      headerFont = ThemeFont.MONTSERRAT, textFont = ThemeFont.OPEN_SANS,
      primary = "#07875F", primaryLight = "#DDF6EC",
      secondary = "#252635", secondaryDark = "#171822",
      textColor = "#252635", textContrast = "#FFFFFF",
    )

    val sunset = ThemeValues(
      headerFont = ThemeFont.PLAYFAIR_DISPLAY, textFont = ThemeFont.LORA,
      primary = "#C95A3D", primaryLight = "#FAE5DF",
      secondary = "#47324A", secondaryDark = "#2B1D2D",
      textColor = "#2B1D2D", textContrast = "#FFFFFF",
    )
  }
}

enum class ThemeSource(val wire: String) {
  BILLING("billing"),
  ORGANIZATION("organization"),
  USER("user"),
  DEFAULT("default"),
  ;

  companion object {
    fun fromWire(wire: String?): ThemeSource? = entries.firstOrNull { it.wire == wire }
  }
}

sealed class ThemeTarget {
  data object User : ThemeTarget()

  data class Organization(val id: OrganizationID) : ThemeTarget()

  data class Billing(val id: BillingID) : ThemeTarget()
}

data class ThemeRecord(
  val ownerName: String,
  val stored: ThemeValues?,
  val effective: ThemeValues,
  val effectiveSource: ThemeSource,
  val canEdit: Boolean,
  val canReset: Boolean,
)
