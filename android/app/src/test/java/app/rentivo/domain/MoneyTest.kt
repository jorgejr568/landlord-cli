package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MoneyTest {

  @Test
  fun moneyAddsCentavosWithoutFloatingPoint() {
    assertEquals(Money(centavos = 245_000), Money(centavos = 180_000) + Money(centavos = 65_000))
  }

  @Test
  fun moneySubtractsCentavosWithoutFloatingPoint() {
    assertEquals(Money(centavos = 115_000), Money(centavos = 180_000) - Money(centavos = 65_000))
  }

  @Test
  fun moneyFormatsBrazilianCurrency() {
    assertEquals("R$ 2.450,00", Money(centavos = 245_000).formatted())
  }

  @Test
  fun moneyFormatsZeroWithTwoDecimals() {
    assertEquals("R$ 0,00", Money.zero.formatted())
  }

  @Test
  fun moneyFormatsNegativeAmountsWithTheSignBeforeTheCurrency() {
    assertEquals("-R$ 0,50", Money(centavos = -50).formatted())
  }

  @Test
  fun moneyGroupsEveryThousandsBoundary() {
    assertEquals("R$ 1.234.567,89", Money(centavos = 123_456_789).formatted())
    assertEquals("R$ 999,99", Money(centavos = 99_999).formatted())
    assertEquals("R$ 1.000,00", Money(centavos = 100_000).formatted())
  }

  @Test
  fun moneySortsByCentavos() {
    assertTrue(Money(centavos = -1) < Money.zero)
    assertTrue(Money.zero < Money(centavos = 1))
  }
}
