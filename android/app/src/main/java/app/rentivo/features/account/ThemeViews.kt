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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.AltRoute
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
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

/**
 * The document-theme editor. Port of `ThemeEditorView` in
 * `ios/Rentivo/Features/Account/ThemeViews.swift`.
 *
 * The only screen that surfaces failures through an alert instead of the app notice banner: the
 * user is mid-edit on a form, and a banner that scrolls away would be missed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeEditorScreen(target: ThemeTarget, onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var record by remember { mutableStateOf<ThemeRecord?>(null) }
  var values by remember { mutableStateOf(ThemeValues.rentivo) }
  var loadedValues by remember { mutableStateOf<ThemeValues?>(null) }
  var error by remember { mutableStateOf<DemoError?>(null) }

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

  Scaffold(
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = { Text(text = "Aparência") },
        navigationIcon = {
          IconButton(onClick = onBack) {
            Icon(imageVector = Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Voltar")
          }
        },
        actions = {
          if (record?.canEdit == true) {
            TextButton(
              onClick = { scope.launch { save() } },
              modifier = Modifier.testTag("theme.save"),
            ) {
              Text(text = "Salvar")
            }
          }
        },
        colors = TopAppBarDefaults.topAppBarColors(
          containerColor = RentivoColors.paper,
          titleContentColor = RentivoColors.ink,
        ),
      )
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
        ThemeSection(title = "Herança") {
          LabeledContent(label = "Responsável", value = loaded.ownerName)
          LabeledContent(
            label = "Origem efetiva",
            value = loaded.effectiveSource.label,
            modifier = Modifier.testTag("theme.source"),
          )
          if (loaded.stored == null) {
            Row(
              modifier = Modifier.padding(top = RentivoSpacing.small),
              horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
              verticalAlignment = Alignment.CenterVertically,
            ) {
              Icon(
                imageVector = Icons.AutoMirrored.Filled.AltRoute,
                contentDescription = null,
                tint = RentivoColors.secondaryInk,
                modifier = Modifier.size(16.dp),
              )
              Text(
                text = "Este nível herda o tema de ${loaded.effectiveSource.label.lowercase()}.",
                style = RentivoTypography.caption,
                color = RentivoColors.secondaryInk,
              )
            }
          }
        }
      }

      ThemeSection(title = "Tipografia") {
        ThemeFontPicker(
          label = "Fonte de títulos",
          selected = values.headerFont,
          testTag = "theme.header-font",
          onSelect = { values = values.copy(headerFont = it) },
        )
        ThemeFontPicker(
          label = "Fonte de texto",
          selected = values.textFont,
          testTag = "theme.text-font",
          onSelect = { values = values.copy(textFont = it) },
        )
      }

      ThemeSection(title = "Cores da API") {
        ThemeColorField(
          title = "Primária",
          value = values.primary,
          onValueChange = { values = values.copy(primary = it) },
        )
        ThemeColorField(
          title = "Primária clara",
          value = values.primaryLight,
          onValueChange = { values = values.copy(primaryLight = it) },
        )
        ThemeColorField(
          title = "Secundária",
          value = values.secondary,
          onValueChange = { values = values.copy(secondary = it) },
        )
        ThemeColorField(
          title = "Secundária escura",
          value = values.secondaryDark,
          onValueChange = { values = values.copy(secondaryDark = it) },
        )
        ThemeColorField(
          title = "Texto",
          value = values.textColor,
          onValueChange = { values = values.copy(textColor = it) },
        )
        ThemeColorField(
          title = "Texto de contraste",
          value = values.textContrast,
          onValueChange = { values = values.copy(textContrast = it) },
        )
      }

      ThemeSection(title = "Prévia") {
        ThemePreview(values = values)
      }

      if (record?.canReset == true) {
        RentivoButton(
          text = "Restaurar herança",
          onClick = { scope.launch { reset() } },
          modifier = Modifier.testTag("theme.reset"),
          color = RentivoColors.coral,
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

@Composable
private fun ThemeSection(title: String, content: @Composable () -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Text(text = title, style = RentivoTypography.metadata, color = RentivoColors.secondaryInk)
    RentivoCard { content() }
  }
}

@Composable
private fun LabeledContent(label: String, value: String, modifier: Modifier = Modifier) {
  Row(
    modifier = modifier.fillMaxWidth().padding(vertical = RentivoSpacing.tiny),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = label,
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Text(text = value, style = RentivoTypography.body, color = RentivoColors.secondaryInk)
  }
}

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
        .padding(vertical = RentivoSpacing.small)
        .testTag(testTag),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = label,
        style = RentivoTypography.body,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      Text(text = selected.wire, style = RentivoTypography.body, color = RentivoColors.secondaryInk)
      Icon(
        imageVector = Icons.Filled.ArrowDropDown,
        contentDescription = null,
        tint = RentivoColors.secondaryInk,
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
 */
@Composable
private fun ThemeColorField(title: String, value: String, onValueChange: (String) -> Unit) {
  Row(
    modifier = Modifier.fillMaxWidth().padding(vertical = RentivoSpacing.tiny),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(
      modifier = Modifier
        .size(24.dp)
        .background(colorFromHex(value) ?: Color.Transparent, CircleShape)
        .border(1.dp, RentivoColors.ink.copy(alpha = 0.4f), CircleShape)
    )
    OutlinedTextField(
      value = value,
      onValueChange = onValueChange,
      label = { Text(text = title) },
      singleLine = true,
      textStyle = RentivoTypography.body.copy(fontFamily = FontFamily.Monospace),
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
      .padding(RentivoSpacing.large),
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
        .padding(RentivoSpacing.large),
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
