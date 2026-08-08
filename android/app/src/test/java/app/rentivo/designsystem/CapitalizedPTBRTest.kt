package app.rentivo.designsystem

import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [capitalizedPTBR] stands in for Swift's `String.capitalized`, so the reference-month labels the
 * Android screens render match the shipped iOS copy character for character.
 */
class CapitalizedPTBRTest {

  private val defaultLocale = Locale.getDefault()

  @After
  fun restoreLocale() {
    Locale.setDefault(defaultLocale)
  }

  @Test
  fun everyWordIsTitleCasedLikeSwift() {
    assertEquals("Agosto De 2026", "agosto de 2026".capitalizedPTBR())
    assertEquals("Janeiro De 2027", "JANEIRO DE 2027".capitalizedPTBR())
  }

  @Test
  fun trailingCharactersOfAWordAreLowercased() {
    assertEquals("Março De 2026", "MARÇO de 2026".capitalizedPTBR())
  }

  @Test
  fun emptyAndBlankInputsSurviveUnchanged() {
    assertEquals("", "".capitalizedPTBR())
    assertEquals("  ", "  ".capitalizedPTBR())
  }

  /** The copy is PT-BR: the device locale must not decide how it is cased. */
  @Test
  fun castingIsLocaleIndependent() {
    Locale.setDefault(Locale.forLanguageTag("tr-TR"))
    assertEquals("Introdução Ii", "introdução ii".capitalizedPTBR())
  }
}
