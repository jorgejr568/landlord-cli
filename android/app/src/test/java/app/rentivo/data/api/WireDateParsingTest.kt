package app.rentivo.data.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class WireDateParsingTest {

  private val saoPaulo = ZoneId.of("America/Sao_Paulo")

  @Test
  fun `dateOnly parses an iso calendar date`() {
    val parsed = WireDate.dateOnly("2026-07-10")

    assertEquals(2026, parsed.year)
    assertEquals(7, parsed.month)
    assertEquals(10, parsed.day)
  }

  @Test
  fun `dateOnly rejects a malformed date instead of crashing`() {
    assertThrows(LiveAPIError.InvalidResponse::class.java) { WireDate.dateOnly("2026-13-01") }
  }

  @Test
  fun `optionalDateOnly keeps null as null rather than an epoch sentinel`() {
    assertNull(WireDate.optionalDateOnly(null))
    assertEquals(WireDate.dateOnly("2026-07-10"), WireDate.optionalDateOnly("2026-07-10"))
  }

  @Test
  fun `isoDate parses fractional-second internet timestamps`() {
    val instant = WireDate.isoDate("2026-07-20T10:15:30.123456+00:00")

    assertEquals(ZonedDateTime.parse("2026-07-20T10:15:30.123456Z").toInstant(), instant)
  }

  @Test
  fun `isoDate parses internet timestamps without a fraction`() {
    val instant = WireDate.isoDate("2026-12-31T23:59:59Z")

    assertEquals(ZonedDateTime.parse("2026-12-31T23:59:59Z").toInstant(), instant)
  }

  @Test
  fun `isoDate reads a naive DATETIME as Sao Paulo wall clock`() {
    val withoutFraction = WireDate.isoDate("2026-07-20T10:15:30").atZone(saoPaulo)
    val withFraction = WireDate.isoDate("2026-07-20T18:42:11.063639").atZone(saoPaulo)

    assertEquals(10, withoutFraction.hour)
    assertEquals(15, withoutFraction.minute)
    assertEquals(20, withoutFraction.dayOfMonth)
    assertEquals(18, withFraction.hour)
  }

  @Test
  fun `isoDate honours an explicit offset over the local fallback`() {
    // 10:15:30 UTC is 07:15 in Sao Paulo (UTC-3); the offset-less formatters must stay a fallback.
    assertEquals(7, WireDate.isoDate("2026-07-20T10:15:30.123456+00:00").atZone(saoPaulo).hour)
  }

  @Test
  fun `isoDate rejects a timestamp no formatter understands`() {
    assertThrows(LiveAPIError.InvalidResponse::class.java) { WireDate.isoDate("ontem") }
  }
}
