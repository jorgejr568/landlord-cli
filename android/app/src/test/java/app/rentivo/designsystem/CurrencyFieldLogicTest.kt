package app.rentivo.designsystem

import app.rentivo.domain.Money
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The pure half of `CurrencyCentavosField`: everything the mask does to a keystroke before Compose
 * is involved.
 *
 * Expectations build the currency prefix from [Money.CURRENCY_PREFIX] rather than spelling it out,
 * because it ends in U+00A0 NO-BREAK SPACE — indistinguishable from a plain space on screen and
 * easily mangled by an editor.
 */
class CurrencyFieldLogicTest {

  private val prefix = Money.CURRENCY_PREFIX

  @Test
  fun plainDigitsParseAsCentavos() {
    assertEquals(245_000L, centavosFromInput("245000"))
    assertEquals(1L, centavosFromInput("1"))
  }

  @Test
  fun formattingCharactersAreStrippedBackOut() {
    assertEquals(245_000L, centavosFromInput("${prefix}2.450,00"))
    assertEquals(50L, centavosFromInput("${prefix}0,50"))
  }

  @Test
  fun emptyAndDigitlessInputCollapseToZero() {
    assertEquals(0L, centavosFromInput(""))
    assertEquals(0L, centavosFromInput(prefix))
    assertEquals(0L, centavosFromInput("abc,-."))
  }

  @Test
  fun leadingZerosAreInsignificant() {
    assertEquals(0L, centavosFromInput("000"))
    assertEquals(7L, centavosFromInput("0007"))
  }

  @Test
  fun inputAboveTheBackendPersistenceCapClampsInsteadOfOverflowing() {
    assertEquals(999_999_999L, centavosFromInput("999999999"))
    assertEquals(MAX_CENTAVOS, centavosFromInput("2147483647"))
    assertEquals(MAX_CENTAVOS, centavosFromInput("2147483648"))
    assertEquals(MAX_CENTAVOS, centavosFromInput("12345678901234567890"))
  }

  @Test
  fun displayTextMatchesThePtBRMoneyMask() {
    assertEquals("${prefix}0,00", displayText(0L))
    assertEquals("${prefix}0,50", displayText(50L))
    assertEquals("${prefix}2.450,00", displayText(245_000L))
    assertEquals("${prefix}9.999.999,99", displayText(999_999_999L))
  }

  @Test
  fun displayTextMatchesMoneyFormatted() {
    assertEquals(Money(centavos = 245_000L).formatted(), displayText(245_000L))
  }

  @Test
  fun parsingAFormattedValueRoundTrips() {
    for (centavos in listOf(0L, 5L, 99L, 100L, 245_000L, 999_999_999L)) {
      assertEquals(centavos, centavosFromInput(displayText(centavos)))
    }
  }

  @Test
  fun typingADigitOntoAFormattedValueShiftsTheAmountLeft() {
    // The mask is right-to-left: appending "5" to "R$ 24,50" yields "R$ 245,05".
    assertEquals(24_505L, centavosFromInput(displayText(2_450L) + "5"))
  }
}
