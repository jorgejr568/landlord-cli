package app.rentivo.features.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.MutationGate
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoListField
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.domain.DemoError
import app.rentivo.domain.ThemeFont
import app.rentivo.domain.ThemeRecord
import app.rentivo.domain.ThemeSource
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** The swatch beside a hex field, at the same 24pt diameter iOS uses. */
private val SwatchSize = 24.dp

/**
 * The preview breathes 4dp tighter than a list row: iOS uses the stock `.padding()` (16pt) here,
 * not the 20pt page rhythm.
 */
private val PreviewPadding = RentivoSpacing.large - 4.dp

/**
 * The document-theme editor. Port of `ThemeEditorView` in
 * `ios/Rentivo/Features/Account/ThemeViews.swift`.
 *
 * The only screen that surfaces failures through an alert instead of the app notice banner: the
 * user is mid-edit on a form, and a banner that scrolls away would be missed.
 */
@Composable
fun ThemeEditorScreen(target: ThemeTarget, onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var record by remember { mutableStateOf<ThemeRecord?>(null) }
  var values by remember { mutableStateOf(ThemeValues.rentivo) }
  var loadedValues by remember { mutableStateOf<ThemeValues?>(null) }
  var error by remember { mutableStateOf<DemoError?>(null) }
  val mutationGate = remember { MutationGate() }

  // True once the user has changed a field since the last successful load/save. Guards against
  // `dataRevision` reloads (triggered by unrelated bumps) silently overwriting in-progress,
  // unsaved color edits.
  val isDirty = loadedValues != null && values != loadedValues

  suspend fun load() {
    try {
      val loaded = app.dependencies.themes.theme(target)
      record = loaded
      values = loaded.stored ?: loaded.effective
      loadedValues = values
    } catch (cancellation: CancellationException) {
      // A restarted or abandoned load is not a failure: surfacing it would raise a spurious "Não foi
      // possível atualizar" alert over a screen that is about to reload anyway.
      throw cancellation
    } catch (failure: Throwable) {
      error = DemoError.from(failure)
    }
  }

  suspend fun save() {
    try {
      app.dependencies.themes.updateTheme(target, values)
      load()
      app.showNotice("Tema atualizado.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (failure: Throwable) {
      error = DemoError.from(failure)
    }
  }

  suspend fun reset() {
    try {
      app.dependencies.themes.resetTheme(target)
      load()
      app.showNotice("Herança de tema restaurada.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (failure: Throwable) {
      error = DemoError.from(failure)
    }
  }

  LaunchedEffect(app.dataRevision) {
    if (isDirty) return@LaunchedEffect
    load()
  }

  AccountScaffold(
    title = "Aparência",
    onBack = onBack,
    actions = {
      if (record?.canEdit == true) {
        AccountToolbarAction {
          TextButton(
            onClick = { scope.launch { mutationGate.run { save() } } },
            enabled = !mutationGate.isRunning,
            modifier = Modifier.testTag("theme.save"),
          ) {
            Text(text = "Salvar", color = RentivoColors.emerald)
          }
        }
      }
    },
  ) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      record?.let { loaded ->
        AccountSection(
          title = "Herança",
          rows = buildList {
            add({ AccountLabeledRow(label = "Responsável", value = loaded.ownerName) })
            add({
              AccountLabeledRow(
                label = "Origem efetiva",
                value = loaded.effectiveSource.label,
                modifier = Modifier.testTag("theme.source"),
              )
            })
            if (loaded.stored == null) {
              add({
                AccountFootnote(
                  text = "Este nível herda o tema de ${loaded.effectiveSource.label.lowercase()}.",
                  icon = Icons.AutoMirrored.Filled.CallSplit,
                )
              })
            }
          },
        )
      }

      AccountSection(
        title = "Tipografia",
        rows = listOf(
          {
            ThemeFontPicker(
              label = "Fonte de títulos",
              selected = values.headerFont,
              testTag = "theme.header-font",
              onSelect = { values = values.copy(headerFont = it) },
            )
          },
          {
            ThemeFontPicker(
              label = "Fonte de texto",
              selected = values.textFont,
              testTag = "theme.text-font",
              onSelect = { values = values.copy(textFont = it) },
            )
          },
        ),
      )

      AccountSection(
        title = "Cores da API",
        rows = listOf(
          {
            ThemeColorField(
              title = "Primária",
              value = values.primary,
              onValueChange = { values = values.copy(primary = it) },
            )
          },
          {
            ThemeColorField(
              title = "Primária clara",
              value = values.primaryLight,
              onValueChange = { values = values.copy(primaryLight = it) },
            )
          },
          {
            ThemeColorField(
              title = "Secundária",
              value = values.secondary,
              onValueChange = { values = values.copy(secondary = it) },
            )
          },
          {
            ThemeColorField(
              title = "Secundária escura",
              value = values.secondaryDark,
              onValueChange = { values = values.copy(secondaryDark = it) },
            )
          },
          {
            ThemeColorField(
              title = "Texto",
              value = values.textColor,
              onValueChange = { values = values.copy(textColor = it) },
            )
          },
          {
            ThemeColorField(
              title = "Texto de contraste",
              value = values.textContrast,
              onValueChange = { values = values.copy(textContrast = it) },
            )
          },
        ),
      )

      AccountSection(
        title = "Prévia",
        rows = listOf({
          Box(
            modifier = Modifier.padding(
              horizontal = RentivoSpacing.large,
              vertical = RentivoSpacing.medium,
            ),
          ) {
            ThemePreview(values = values)
          }
        }),
      )

      if (record?.canReset == true) {
        AccountSection(
          rows = listOf({
            AccountTextButtonRow(
              title = "Restaurar herança",
              destructive = true,
              modifier = Modifier.testTag("theme.reset"),
              onClick = { scope.launch { mutationGate.run { reset() } } },
            )
          }),
        )
      }
    }
  }

  error?.let { shown ->
    AlertDialog(
      onDismissRequest = { error = null },
      title = { Text(text = "Não foi possível atualizar") },
      text = { Text(text = shown.message) },
      confirmButton = {
        TextButton(onClick = { error = null }, modifier = Modifier.testTag("theme.error.ok")) {
          Text(text = "OK")
        }
      },
      containerColor = RentivoColors.surface,
    )
  }
}

/** The iOS `Picker` row: label, the selected value in the accent tint, and an up/down chevron. */
@Composable
private fun ThemeFontPicker(
  label: String,
  selected: ThemeFont,
  testTag: String,
  onSelect: (ThemeFont) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }

  Box(modifier = Modifier.fillMaxWidth()) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .clickable { expanded = true }
        .heightIn(min = AccountRowMinHeight)
        .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium)
        .testTag(testTag),
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = label,
        style = RentivoTypography.body,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      Text(text = selected.wire, style = RentivoTypography.body, color = RentivoColors.emerald)
      Icon(
        imageVector = Icons.Filled.UnfoldMore,
        contentDescription = null,
        tint = RentivoColors.emerald,
        modifier = Modifier.size(16.dp),
      )
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
      ThemeFont.entries.forEach { font ->
        DropdownMenuItem(
          text = { Text(text = font.wire) },
          onClick = {
            onSelect(font)
            expanded = false
          },
        )
      }
    }
  }
}

/**
 * A hex field with a live swatch. Deliberately not a system color picker: the API stores plain hex
 * strings, and round-tripping through a platform picker would silently rewrite values the user
 * pasted from a brand guide.
 *
 * The field is borderless like every other list row; the color name is its placeholder, exactly as
 * the iOS `TextField(title, text:)` renders it.
 */
@Composable
private fun ThemeColorField(title: String, value: String, onValueChange: (String) -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(
      modifier = Modifier
        .size(SwatchSize)
        .background(colorFromHex(value) ?: Color.Transparent, CircleShape)
        .border(1.dp, RentivoColors.ink.copy(alpha = 0.4f), CircleShape)
    )
    RentivoListField(
      value = value,
      onValueChange = onValueChange,
      placeholder = title,
      monospace = true,
      keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
      modifier = Modifier.weight(1f),
    )
  }
}

/** A local, offline rendering of what the generated invoice header will look like. */
@Composable
private fun ThemePreview(values: ThemeValues) {
  val textColor = colorFromHex(values.textColor) ?: RentivoColors.ink

  Column(
    modifier = Modifier
      .fillMaxWidth()
      .background(
        colorFromHex(values.primaryLight) ?: RentivoColors.emeraldLight,
        RoundedCornerShape(16.dp),
      )
      .padding(PreviewPadding),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
  ) {
    Text(
      text = "Fatura Rentivo",
      style = RentivoTypography.title.copy(fontWeight = FontWeight.Bold),
      color = textColor,
    )
    Text(
      text = "Uma prévia local das cores do documento.",
      style = RentivoTypography.body,
      color = textColor,
    )
    Text(
      text = "R$ 2.450,00",
      style = RentivoTypography.money.copy(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Bold,
      ),
      color = colorFromHex(values.textContrast) ?: Color.White,
      textAlign = TextAlign.Center,
      modifier = Modifier
        .fillMaxWidth()
        .background(
          colorFromHex(values.primary) ?: RentivoColors.emerald,
          RoundedCornerShape(12.dp),
        )
        .padding(PreviewPadding),
    )
  }
}

/** The PT-BR label of the level a theme is inherited from. */
private val ThemeSource.label: String
  get() = when (this) {
    ThemeSource.BILLING -> "Cobrança"
    ThemeSource.ORGANIZATION -> "Organização"
    ThemeSource.USER -> "Usuário"
    ThemeSource.DEFAULT -> "Padrão Rentivo"
  }

/**
 * Parses `#RRGGBB` / `RRGGBB` and nothing else — a partially typed value leaves the swatch clear
 * rather than snapping to a misleading color.
 */
private fun colorFromHex(hex: String): Color? {
  val value = hex.trim('#')
  if (value.length != 6 || value.any { it.digitToIntOrNull(radix = 16) == null }) return null
  val rgb = value.toInt(radix = 16)
  return Color(
    red = ((rgb shr 16) and 0xFF) / 255f,
    green = ((rgb shr 8) and 0xFF) / 255f,
    blue = (rgb and 0xFF) / 255f,
  )
}
