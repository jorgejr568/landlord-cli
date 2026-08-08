package app.rentivo.data.api

import app.rentivo.domain.DateOnly
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoField

/**
 * Parsing for the date and timestamp shapes the server puts on the wire, shared by every
 * [APIRentivoStore] decoder. The formatters are immutable and stateless, so the shared instances
 * are safe to reuse from any thread.
 */
object WireDate {

  /**
   * A present but malformed date string surfaces as a decode error via [DateOnly]'s failable wire
   * parser instead of reaching the `require`-enforcing [DateOnly] constructor and crashing the
   * process on out-of-range components.
   */
  fun dateOnly(value: String): DateOnly =
    DateOnly.fromIso8601String(value) ?: throw LiveAPIError.InvalidResponse

  /**
   * `due_date` is nullable on the wire. A `null` means the bill genuinely has no due date yet, so
   * it stays `null` rather than collapsing to an epoch sentinel that would surface in the UI as
   * "Vence 01/01/1970".
   */
  fun optionalDateOnly(value: String?): DateOnly? = value?.let { dateOnly(it) }

  private val SAO_PAULO: ZoneId = ZoneId.of("America/Sao_Paulo")

  // The backend emits fractional-second timestamps (microseconds); try that format first and fall
  // back to the plain internet-date-time form. A total parse failure surfaces as a decode error
  // instead of silently defaulting to the epoch.
  private val offsetDateTimeWithFraction: DateTimeFormatter = DateTimeFormatterBuilder()
    .appendPattern("uuuu-MM-dd'T'HH:mm:ss")
    .appendFraction(ChronoField.NANO_OF_SECOND, 1, 9, true)
    .appendOffsetId()
    .toFormatter()

  private val offsetDateTime: DateTimeFormatter = DateTimeFormatterBuilder()
    .appendPattern("uuuu-MM-dd'T'HH:mm:ss")
    .appendOffsetId()
    .toFormatter()

  // Timestamps read straight out of a naive `DATETIME` column reach us without a timezone
  // designator (e.g. `2026-07-28T13:28:55`). The internet-date-time formatters above require one,
  // so they reject those outright and a display-only date takes down the whole screen. They are
  // São Paulo wall clock on the wire, so parse them in that zone.
  //
  // These are strictly a fallback: they carry no offset field at all, so handing them an
  // offset-bearing string must never be how a `Z` timestamp gets interpreted. [isoDate] therefore
  // only reaches them once the offset-bearing formatters have failed.
  private val localDateTimeWithFraction: DateTimeFormatter = DateTimeFormatterBuilder()
    .appendPattern("uuuu-MM-dd'T'HH:mm:ss")
    .appendFraction(ChronoField.NANO_OF_SECOND, 1, 9, true)
    .toFormatter()

  private val localDateTime: DateTimeFormatter = DateTimeFormatterBuilder()
    .appendPattern("uuuu-MM-dd'T'HH:mm:ss")
    .toFormatter()

  /** The fallback order below is load-bearing — see the comments on each formatter. */
  fun isoDate(value: String): Instant {
    offsetInstant(value, offsetDateTimeWithFraction)?.let { return it }
    offsetInstant(value, offsetDateTime)?.let { return it }
    localInstant(value, localDateTimeWithFraction)?.let { return it }
    localInstant(value, localDateTime)?.let { return it }
    throw LiveAPIError.InvalidResponse
  }

  private fun offsetInstant(value: String, formatter: DateTimeFormatter): Instant? = try {
    OffsetDateTime.parse(value, formatter).toInstant()
  } catch (error: DateTimeParseException) {
    null
  }

  private fun localInstant(value: String, formatter: DateTimeFormatter): Instant? = try {
    LocalDateTime.parse(value, formatter).atZone(SAO_PAULO).toInstant()
  } catch (error: DateTimeParseException) {
    null
  }
}
