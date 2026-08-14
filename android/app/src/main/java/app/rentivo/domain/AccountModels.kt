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
      canManage = false, canInvite = true, canCreateBilling = true, canViewBillingStats = true,
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
)

data class OrganizationDraft(
  val name: String,
  val pix: PixConfiguration?,
) {
  val isValid: Boolean get() = name.trim().isNotEmpty()
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

data class APIKeyGrant(
  val resourceType: WorkspaceResourceType,
  val resourceID: WorkspaceID,
  val available: Boolean = true,
)

/** Lightweight server-provided choice for an API-key grant; no organization detail hydration. */
data class APIKeyWorkspaceOption(
  val resourceType: WorkspaceResourceType,
  val resourceID: WorkspaceID,
  val name: String?,
)

data class APIKeyOptions(
  val scopes: Set<APIKeyScope>,
  val workspaces: List<APIKeyWorkspaceOption>,
  val defaultExpirationDays: Int,
  val maxExpirationDays: Int,
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
  /** Grants the server redacted so their identifiers cannot be safely round-tripped. */
  val unavailableGrantCount: Int = 0,
  /** Scopes unknown to this app version, which must remain server-owned during an edit. */
  val unavailableScopeCount: Int = 0,
)

data class APIKeyDraft(
  val name: String,
  val scopes: Set<APIKeyScope>,
  val grants: List<APIKeyGrant>,
  val expiresAt: Instant,
  /** PATCH omits grants unless the edit form explicitly changed the visible selection. */
  val shouldUpdateGrants: Boolean = true,
  /** PATCH omits scopes unless the edit form explicitly changed the visible selection. */
  val shouldUpdateScopes: Boolean = true,
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

object APIKeyNameRule {
  fun validationMessage(value: String): String? = when {
    value.trim().isEmpty() -> "Informe o nome da chave."
    value.trim().length > 255 -> "O nome deve ter no máximo 255 caracteres."
    else -> null
  }
}

/** Pure form policy that prevents a partial visible grant set from replacing hidden grants. */
data class APIKeyGrantEditRule(
  val originalGrantIDs: Set<WorkspaceID>,
  val unavailableGrantCount: Int,
) {
  val canEdit: Boolean get() = unavailableGrantCount == 0

  fun shouldUpdate(selectedGrantIDs: Set<WorkspaceID>): Boolean =
    canEdit && selectedGrantIDs != originalGrantIDs
}

/** Pure form policy that prevents known scopes from replacing server scopes this build cannot name. */
data class APIKeyScopeEditRule(
  val originalScopes: Set<APIKeyScope>,
  val unavailableScopeCount: Int,
) {
  val canEdit: Boolean get() = unavailableScopeCount == 0

  fun shouldUpdate(selectedScopes: Set<APIKeyScope>): Boolean =
    canEdit && selectedScopes != originalScopes
}

data class CreatedAPIKeySecret(
  val metadata: APIKeyMetadata,
  val secret: String,
)

/** Server-authoritative guard for the irreversible account-deletion flow. */
data class AccountDeletionReadiness(
  val canDelete: Boolean,
  /** A stable backend code; unknown values remain visible rather than being silently treated safe. */
  val reason: String? = null,
) {
  val blockerMessage: String?
    get() = when (reason) {
      "sole_organization_admin" ->
        "Transfira ou remova a administração das organizações antes de excluir sua conta."
      null -> null
      else -> "A exclusão da conta está indisponível no momento."
    }
}

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

object ThemeFormRules {
  private val hexColor = Regex("^#[0-9A-Fa-f]{6}$")

  fun isHexColor(value: String): Boolean = hexColor.matches(value)

  fun invalidColorNames(values: ThemeValues): List<String> = listOf(
    "Primária" to values.primary,
    "Primária clara" to values.primaryLight,
    "Secundária" to values.secondary,
    "Secundária escura" to values.secondaryDark,
    "Texto" to values.textColor,
    "Texto de contraste" to values.textContrast,
  ).mapNotNull { (name, value) -> name.takeUnless { isHexColor(value) } }

  fun contrastWarnings(values: ThemeValues): List<String> {
    if (invalidColorNames(values).isNotEmpty()) return emptyList()
    return buildList {
      if (contrastRatio(values.textContrast, values.primary) < 4.5) {
        add("O texto de contraste pode ficar difícil de ler sobre a cor primária.")
      }
      if (contrastRatio(values.textColor, values.primaryLight) < 4.5) {
        add("O texto pode ficar difícil de ler sobre a cor primária clara.")
      }
    }
  }

  private fun contrastRatio(foreground: String, background: String): Double {
    val first = luminance(foreground)
    val second = luminance(background)
    return (maxOf(first, second) + 0.05) / (minOf(first, second) + 0.05)
  }

  private fun luminance(value: String): Double {
    val raw = value.drop(1).toLong(radix = 16)
    val channels = listOf(raw shr 16, (raw shr 8) and 0xFF, raw and 0xFF).map { channel ->
      val normalized = channel.toDouble() / 255.0
      if (normalized <= 0.03928) normalized / 12.92
      else Math.pow((normalized + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
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
