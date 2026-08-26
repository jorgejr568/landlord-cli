package app.rentivo.domain

import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import java.util.UUID

/** Screen-local loading contract shared by every feature. */
sealed class LoadState<out Value> {
  /** The loaded payload, or `null` in every other state. */
  abstract val value: Value?

  data object Idle : LoadState<Nothing>() {
    override val value: Nothing? = null
  }

  data object Loading : LoadState<Nothing>() {
    override val value: Nothing? = null
  }

  data class Loaded<Value>(override val value: Value) : LoadState<Value>()

  data object Empty : LoadState<Nothing>() {
    override val value: Nothing? = null
  }

  data class Failed(val error: DemoError) : LoadState<Nothing>() {
    override val value: Nothing? = null
  }
}

/** Pure state transition used by forms to make a second submit a no-op until the first completes. */
data class FormSubmitState(val isSubmitting: Boolean) {
  fun start(): FormSubmitState = if (isSubmitting) this else submitting

  fun finish(): FormSubmitState = idle

  companion object {
    val idle = FormSubmitState(isSubmitting = false)
    val submitting = FormSubmitState(isSubmitting = true)
  }
}

/**
 * Kotlin analogue of Swift's `LocalizedError`: an error that carries user-facing PT-BR copy.
 * [DemoError.from] preserves the description of anything implementing it (notably `LiveAPIError`)
 * and falls back to generic copy for everything else.
 */
interface LocalizedError {
  val errorDescription: String?
}

/** The single user-facing error type. Equality is by message so tests can compare constants. */
class DemoError(override val message: String) : Exception(message), LocalizedError {

  override val errorDescription: String get() = message

  override fun equals(other: Any?): Boolean = other is DemoError && other.message == message

  override fun hashCode(): Int = message.hashCode()

  override fun toString(): String = message

  companion object {
    /** Unwraps an existing [DemoError], preserves a [LocalizedError] message, or falls back. */
    fun from(error: Throwable): DemoError = when {
      error is DemoError -> error
      error is LocalizedError && error.errorDescription != null ->
        DemoError(message = error.errorDescription!!)
      else -> DemoError(message = "Não foi possível concluir esta ação. Tente novamente.")
    }

    val operationFailed = DemoError(
      message = "Não foi possível concluir esta ação de demonstração."
    )
    val invalidBillTransition = DemoError(
      message = "Esta mudança de status não é permitida."
    )
    val staleBillStatus = DemoError(
      message = "O status da fatura foi alterado. Atualize a página e tente novamente."
    )
    val resourceNotFound = DemoError(
      message = "O item solicitado não foi encontrado."
    )
    val permissionDenied = DemoError(
      message = "Seu perfil de demonstração não permite esta ação."
    )
    val invalidAmount = DemoError(
      message = "O valor informado deve ser maior que zero."
    )
    val invalidDescription = DemoError(
      message = "Informe uma descrição com no máximo 2000 caracteres."
    )
  }
}

object StableID {
  const val userAna: Int = 1
  val organizationHorizonte = OrganizationID(rawValue = "00000000-0000-0000-0000-000000000010")
  val billingAurora101 = BillingID(rawValue = "00000000-0000-0000-0000-000000000101")
  val billingAurora202 = BillingID(rawValue = "00000000-0000-0000-0000-000000000102")
  val billingSolNascente303 = BillingID(rawValue = "00000000-0000-0000-0000-000000000103")
  val billingVilaFlores1 = BillingID(rawValue = "00000000-0000-0000-0000-000000000104")
  val billingTorreNorte501 = BillingID(rawValue = "00000000-0000-0000-0000-000000000105")
  val billingCentro12 = BillingID(rawValue = "00000000-0000-0000-0000-000000000106")
  val billDraft = BillID(rawValue = "00000000-0000-0000-0000-000000001001")
  val billPublished = BillID(rawValue = "00000000-0000-0000-0000-000000001002")
  val billSent = BillID(rawValue = "00000000-0000-0000-0000-000000001003")
  val billPaid = BillID(rawValue = "00000000-0000-0000-0000-000000001004")
  val billCancelled = BillID(rawValue = "00000000-0000-0000-0000-000000001005")
  val billDelayed = BillID(rawValue = "00000000-0000-0000-0000-000000001006")
  val invitationHorizonte = InvitationID(rawValue = "00000000-0000-0000-0000-000000003001")
  val apiKeyDashboard = APIKeyID(rawValue = "00000000-0000-0000-0000-000000004001")
}

/**
 * A calendar-agnostic date. The constructor rejects out-of-range components; malformed wire data
 * goes through [fromIso8601String], which answers `null` instead of throwing.
 */
data class DateOnly(
  val year: Int,
  val month: Int,
  val day: Int,
) : Comparable<DateOnly> {

  init {
    require(month in 1..12) { "Month must be between 1 and 12" }
    require(day in 1..31) { "Day must be between 1 and 31" }
  }

  val iso8601: String get() = String.format(Locale.ROOT, "%04d-%02d-%02d", year, month, day)

  /**
   * PT-BR display representation, e.g. "10/08/2026". The dd/MM/yyyy ordering is the Brazilian
   * convention regardless of the device's locale, so it is built from the stored components.
   */
  val displayFormatted: String get() = String.format(Locale.ROOT, "%02d/%02d/%04d", day, month, year)

  override fun compareTo(other: DateOnly): Int =
    compareValuesBy(this, other, DateOnly::year, DateOnly::month, DateOnly::day)

  /**
   * The reverse bridge, for seeding a date picker. [fromIso8601String] only range-checks the day
   * as 1..31 without consulting the month's length, so a wire value like "2026-02-31" can reach
   * here; day-of-month arithmetic normalizes such components (into March) rather than throwing.
   */
  fun resolvedDate(): LocalDate = LocalDate.of(year, month, 1).plusDays((day - 1).toLong())

  companion object {
    /**
     * Failable parsing intended for the wire boundary: malformed server data (or user input)
     * returns `null` instead of throwing.
     */
    fun fromIso8601String(iso8601String: String): DateOnly? {
      val parts = iso8601String.split("-")
      if (parts.size != 3) return null
      val year = parts[0].toIntOrNull() ?: return null
      val month = parts[1].toIntOrNull() ?: return null
      val day = parts[2].toIntOrNull() ?: return null
      if (month !in 1..12 || day !in 1..31) return null
      return DateOnly(year = year, month = month, day = day)
    }

    /** Bridges a picker selection into the calendar-agnostic domain representation. */
    fun from(date: LocalDate): DateOnly =
      DateOnly(year = date.year, month = date.monthValue, day = date.dayOfMonth)
  }
}

data class ReferenceMonth(
  val year: Int,
  val month: Int,
) : Comparable<ReferenceMonth> {

  init {
    require(month in 1..12) { "Month must be between 1 and 12" }
  }

  val apiValue: String get() = String.format(Locale.ROOT, "%04d-%02d", year, month)

  val label: String get() = "${MONTH_NAMES[month - 1]} de $year"

  /** PT-BR display representation, e.g. "agosto de 2026". */
  val displayFormatted: String get() = label

  /**
   * The due date a new bill starts from: day 10 of the month *after* the reference month. The
   * reference month says which period the bill covers; the due date says when the money is owed,
   * and in practice that lands in the following month.
   */
  val defaultDueDate: DateOnly
    get() {
      val rollsOver = month == 12
      return DateOnly(
        year = if (rollsOver) year + 1 else year,
        month = if (rollsOver) 1 else month + 1,
        day = 10,
      )
    }

  override fun compareTo(other: ReferenceMonth): Int =
    compareValuesBy(this, other, ReferenceMonth::year, ReferenceMonth::month)

  companion object {
    private val MONTH_NAMES = listOf(
      "janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    )

    /** Failable parsing intended for the wire boundary. */
    fun fromApiValue(apiValue: String): ReferenceMonth? {
      val parts = apiValue.split("-")
      if (parts.size != 2) return null
      val year = parts[0].toIntOrNull() ?: return null
      val month = parts[1].toIntOrNull() ?: return null
      if (month !in 1..12) return null
      return ReferenceMonth(year = year, month = month)
    }
  }
}

data class UserProfile(
  val id: Int,
  val email: String,
  val pix: PixConfiguration? = null,
)

/** Bcrypt's public input boundary is 72 encoded bytes, not 72 Unicode characters. */
object PasswordInput {
  const val MAX_BCRYPT_UTF8_BYTES = 72
  private const val TOO_LONG_MESSAGE = "A senha deve ter no máximo 72 bytes UTF-8."

  fun validationMessage(value: String): String? =
    TOO_LONG_MESSAGE.takeIf { value.toByteArray(Charsets.UTF_8).size > MAX_BCRYPT_UTF8_BYTES }

  fun validationMessage(vararg values: String): String? =
    values.firstNotNullOfOrNull(::validationMessage)
}

object TOTPCodeRule {
  private val sixDigits = Regex("^[0-9]{6}$")

  fun validationMessage(value: String): String? =
    "Informe um código de seis dígitos.".takeUnless { sixDigits.matches(value) }
}

/** Shared lossless PIX form boundary: only an entirely empty or entirely complete triple is valid. */
data class PixFormFields(
  val key: String,
  val merchantName: String,
  val merchantCity: String,
) {
  private val normalizedValues: List<String>
    get() = listOf(key.trim(), merchantName.trim(), merchantCity.trim())

  val isValid: Boolean
    get() = normalizedValues.all(String::isEmpty) || normalizedValues.all(String::isNotEmpty)

  val validationMessage: String?
    get() = if (isValid) null else "Informe a chave, o nome e a cidade do recebedor para usar PIX."

  val configuration: PixConfiguration?
    get() = normalizedValues.takeIf { isValid && it.first().isNotEmpty() }?.let { values ->
      PixConfiguration(key = values[0], merchantName = values[1], merchantCity = values[2])
    }
}

data class ProfilePIXForm(
  var key: String,
  var merchantName: String,
  var merchantCity: String,
) {
  /** An empty triple explicitly clears PIX; a partial triple deliberately has no payload. */
  val configuration: PixConfiguration?
    get() = fields.configuration

  val validationMessage: String?
    get() = fields.validationMessage

  private val fields: PixFormFields
    get() = PixFormFields(key = key, merchantName = merchantName, merchantCity = merchantCity)

  val isSavable: Boolean
    get() {
      val normalizedName = merchantName.trim()
      val normalizedCity = merchantCity.trim()
      return fields.isValid &&
        normalizedName.codePointCount(0, normalizedName.length) <= 255 &&
        normalizedCity.codePointCount(0, normalizedCity.length) <= 255
    }

  companion object {
    fun from(profile: UserProfile? = null): ProfilePIXForm = ProfilePIXForm(
      key = profile?.pix?.key ?: "",
      merchantName = profile?.pix?.merchantName ?: "",
      merchantCity = profile?.pix?.merchantCity ?: "",
    )
  }
}

enum class ActivityKind(val wire: String) {
  BILLING("billing"),
  BILL("bill"),
  EXPENSE("expense"),
  ORGANIZATION("organization"),
  INVITATION("invitation"),
  SECURITY("security"),
  API_KEY("api_key"),
  THEME("theme"),
  ;

  companion object {
    fun fromWire(wire: String?): ActivityKind? = entries.firstOrNull { it.wire == wire }
  }
}

data class RecentActivity(
  val id: UUID,
  val kind: ActivityKind,
  val title: String,
  val detail: String,
  val occurredAt: Instant,
)
