package app.rentivo.designsystem

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.rentivo.domain.Money

/**
 * The largest number of digits the field accepts, i.e. `R$ 9.999.999,99`.
 *
 * The iOS field parses the typed digits with `Int(digits)`, and Swift's `Int` is 64-bit, so it can
 * absorb far more digits before failing. Kotlin's `Int` is 32-bit and the domain stores centavos as
 * `Int`, so anything past 10 digits would overflow `toIntOrNull()` and silently reset the amount to
 * zero. Capping the input instead makes the extra keystrokes no-ops, which is the behavior users
 * expect from a masked field and keeps the bound value stable.
 */
private const val MAX_DIGITS = 9

/**
 * Parses whatever the user typed into an integer centavos amount: non-digits are dropped, leading
 * zeros collapse, an empty result is 0, and input past [MAX_DIGITS] significant digits is ignored.
 */
fun centavosFromInput(text: String): Int {
  val digits = text.filter { it.isDigit() }.trimStart('0')
  if (digits.isEmpty()) return 0
  return digits.take(MAX_DIGITS).toIntOrNull() ?: 0
}

/** The masked representation of [centavos], e.g. `245000` -> `R$ 2.450,00`. */
fun displayText(centavos: Int): String = Money(centavos = centavos).formatted()

/**
 * A text field that edits an `Int` centavos value as pt-BR currency: typing "245000" displays
 * "R$ 2.450,00". The amount itself never passes through `Float`/`Double` — only
 * [Money.formatted] touches the presentation.
 *
 * Unlike the iOS version, which mirrors the text into its own `@State` and reconciles it in two
 * `onChange` handlers, the displayed text here is derived from [centavos] on every recomposition.
 * That makes external value changes reformat for free and removes the possibility of the two
 * copies drifting apart. The caret always sits at the end of the value, which is the natural
 * behavior for a right-to-left digit mask.
 */
@Composable
fun CurrencyCentavosField(
  label: String,
  centavos: Int,
  onCentavosChange: (Int) -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  OutlinedTextField(
    value = displayText(centavos),
    onValueChange = { onCentavosChange(centavosFromInput(it)) },
    modifier = modifier.semantics { contentDescription = label },
    enabled = enabled,
    label = { Text(text = label) },
    singleLine = true,
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
    textStyle = RentivoTypography.money,
    shape = RoundedCornerShape(14.dp),
    colors = OutlinedTextFieldDefaults.colors(
      focusedBorderColor = RentivoColors.ink,
      unfocusedBorderColor = RentivoColors.ink,
      focusedContainerColor = RentivoColors.surface,
      unfocusedContainerColor = RentivoColors.surface,
      focusedTextColor = RentivoColors.ink,
      unfocusedTextColor = RentivoColors.ink,
      focusedLabelColor = RentivoColors.secondaryInk,
      unfocusedLabelColor = RentivoColors.secondaryInk,
    ),
  )
}
