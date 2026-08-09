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
    assertEquals(245_000, centavosFromInput("245000"))
    assertEquals(1, centavosFromInput("1"))
  }

  @Test
  fun formattingCharactersAreStrippedBackOut() {
    assertEquals(245_000, centavosFromInput("${prefix}2.450,00"))
    assertEquals(50, centavosFromInput("${prefix}0,50"))
  }

  @Test
  fun emptyAndDigitlessInputCollapseToZero() {
    assertEquals(0, centavosFromInput(""))
    assertEquals(0, centavosFromInput(prefix))
    assertEquals(0, centavosFromInput("abc,-."))
  }

  @Test
  fun leadingZerosAreInsignificant() {
    assertEquals(0, centavosFromInput("000"))
    assertEquals(7, centavosFromInput("0007"))
  }

  @Test
  fun inputPastTheDigitCapIsIgnoredInsteadOfOverflowing() {
    assertEquals(999_999_999, centavosFromInput("999999999"))
    // A tenth digit would exceed what Int centavos can hold, so it is dropped rather than
    // wrapping the amount around or resetting it to zero.
    assertEquals(999_999_999, centavosFromInput("9999999991"))
    assertEquals(123_456_789, centavosFromInput("12345678901234567890"))
  }

  @Test
  fun displayTextMatchesThePtBRMoneyMask() {
    assertEquals("${prefix}0,00", displayText(0))
    assertEquals("${prefix}0,50", displayText(50))
    assertEquals("${prefix}2.450,00", displayText(245_000))
    assertEquals("${prefix}9.999.999,99", displayText(999_999_999))
  }

  @Test
  fun displayTextMatchesMoneyFormatted() {
    assertEquals(Money(centavos = 245_000).formatted(), displayText(245_000))
  }

  @Test
  fun parsingAFormattedValueRoundTrips() {
    for (centavos in listOf(0, 5, 99, 100, 245_000, 999_999_999)) {
      assertEquals(centavos, centavosFromInput(displayText(centavos)))
    }
  }

  @Test
  fun typingADigitOntoAFormattedValueShiftsTheAmountLeft() {
    // The mask is right-to-left: appending "5" to "R$ 24,50" yields "R$ 245,05".
    assertEquals(24_505, centavosFromInput(displayText(2_450) + "5"))
  }
}
