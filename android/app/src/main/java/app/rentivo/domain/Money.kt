package app.rentivo.domain

import kotlin.math.absoluteValue

/**
 * Integer centavos, never floating point.
 *
 * Formatting is hand-rolled instead of delegated to [java.text.NumberFormat] so the output is
 * identical on every device regardless of the system locale or the JDK's CLDR revision, and
 * byte-for-byte identical to the iOS app's `Money.formatted()`.
 */
data class Money(val centavos: Int) : Comparable<Money> {

  operator fun plus(other: Money): Money = Money(centavos + other.centavos)

  operator fun minus(other: Money): Money = Money(centavos - other.centavos)

  override fun compareTo(other: Money): Int = centavos.compareTo(other.centavos)

  /** e.g. `R$ 2.450,00`, and `-R$ 0,50` for negative amounts. */
  fun formatted(): String {
    val magnitude = centavos.toLong().absoluteValue
    val units = magnitude / 100
    val fraction = magnitude % 100
    val sign = if (centavos < 0) "-" else ""
    return sign + CURRENCY_PREFIX + groupThousands(units) + DECIMAL_SEPARATOR +
      fraction.toString().padStart(2, '0')
  }

  private fun groupThousands(units: Long): String {
    val digits = units.toString()
    val builder = StringBuilder(digits.length + digits.length / 3)
    for ((index, digit) in digits.withIndex()) {
      if (index > 0 && (digits.length - index) % 3 == 0) builder.append(GROUPING_SEPARATOR)
      builder.append(digit)
    }
    return builder.toString()
  }

  companion object {
    val zero = Money(centavos = 0)

    /** `R$` followed by U+00A0 NO-BREAK SPACE, matching the pt-BR currency convention. */
    const val CURRENCY_PREFIX: String = "R$ "
    private const val GROUPING_SEPARATOR = '.'
    private const val DECIMAL_SEPARATOR = ','
  }
}
