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
 * Largest individual value the backend can persist in its PostgreSQL `INTEGER` amount columns.
 */
const val MAX_CENTAVOS = Money.MAX_PERSISTED_CENTAVOS

/**
 * Parses whatever the user typed into an integer centavos amount: non-digits are dropped, leading
 * zeros collapse, an empty result is 0, and larger values clamp to [MAX_CENTAVOS].
 */
fun centavosFromInput(text: String): Long {
  val digits = text.filter { it.isDigit() }.trimStart('0')
  if (digits.isEmpty()) return 0L
  return digits.toLongOrNull()?.coerceAtMost(MAX_CENTAVOS) ?: MAX_CENTAVOS
}

/** The masked representation of [centavos], e.g. `245000` -> `R$ 2.450,00`. */
fun displayText(centavos: Long): String = Money(centavos = centavos).formatted()

/**
 * A text field that edits a `Long` centavos value as pt-BR currency: typing "245000" displays
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
  centavos: Long,
  onCentavosChange: (Long) -> Unit,
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
