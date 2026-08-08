package app.rentivo.features.demo

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Handyman
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.SyncProblem
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.rentivoPage

/**
 * The developer-facing switchboard for the in-memory demo store, ported from
 * `ios/Rentivo/Features/Demo/DemoScenariosView.swift`.
 *
 * Every control here mutates only the mock repositories, so the screen is reachable from the
 * account tab in demo builds and is dropped from production navigation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DemoScenariosScreen(onBack: () -> Unit) {
  val app = LocalAppModel.current
  var confirmingReset by remember { mutableStateOf(false) }

  Scaffold(
    modifier = Modifier.rentivoPage(),
    containerColor = Color.Transparent,
    topBar = {
      TopAppBar(
        title = { Text(text = "Cenários", style = RentivoTypography.title) },
        navigationIcon = {
          IconButton(onClick = onBack) {
            Icon(imageVector = Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Voltar")
          }
        },
        colors = TopAppBarDefaults.topAppBarColors(
          containerColor = Color.Transparent,
          titleContentColor = RentivoColors.ink,
          navigationIconContentColor = RentivoColors.ink,
        ),
      )
    },
  ) { insets ->
    Column(
      modifier = Modifier
        .padding(insets)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      RentivoCard {
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Icon(
            imageVector = Icons.Filled.Handyman,
            contentDescription = null,
            tint = RentivoColors.secondaryInk,
            modifier = Modifier.size(20.dp),
          )
          Text(
            text = "Estas opções alteram apenas o repositório em memória e serão removidas da " +
              "navegação de produção.",
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
        }
      }

      DemoSection(title = "Estados de leitura", icon = Icons.Filled.Tune) {
        SettingRow(
          title = "Atraso de 350 ms",
          enabled = app.demoSettings.delayEnabled,
          testTag = "demo.delay-mode",
          onClick = { app.setDelayEnabled(!app.demoSettings.delayEnabled) },
        )
        HorizontalDivider(color = RentivoColors.ink.copy(alpha = 0.12f))
        SettingRow(
          title = "Conteúdo vazio",
          enabled = app.demoSettings.emptyMode,
          testTag = "demo.empty-mode",
          onClick = { app.setEmptyMode(!app.demoSettings.emptyMode) },
        )
        HorizontalDivider(color = RentivoColors.ink.copy(alpha = 0.12f))
        SettingRow(
          title = "Permissões de visualizador",
          enabled = app.demoSettings.viewerMode,
          testTag = "demo.viewer-mode",
          onClick = { app.setViewerMode(!app.demoSettings.viewerMode) },
        )
      }

      DemoSection(title = "Falhas recuperáveis", icon = Icons.Outlined.ReportProblem) {
        ActionRow(
          title = "Falhar a próxima operação",
          icon = Icons.Filled.SyncProblem,
          color = RentivoColors.emerald,
          testTag = "demo.fail-next",
          onClick = {
            app.failNextOperation()
            app.showNotice(
              "A próxima operação falhará de forma controlada.",
              AppNotice.Kind.INFORMATION,
            )
          },
        )
      }

      DemoSection(title = "Dados canônicos", icon = Icons.Filled.Inventory2) {
        ActionRow(
          title = "Restaurar toda a demonstração",
          icon = null,
          color = RentivoColors.coral,
          testTag = "demo.reset",
          onClick = { confirmingReset = true },
        )
      }
    }
  }

  if (confirmingReset) {
    AlertDialog(
      onDismissRequest = { confirmingReset = false },
      title = { Text(text = "Restaurar todos os dados?") },
      text = {
        Text(
          text = "Cobranças, faturas, despesas, organizações e configurações voltarão ao " +
            "estado inicial.",
        )
      },
      confirmButton = {
        TextButton(
          onClick = {
            confirmingReset = false
            app.resetDemo()
            app.showNotice("Demonstração restaurada.")
          },
        ) {
          Text(text = "Restaurar", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingReset = false }) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
      containerColor = RentivoColors.surface,
      titleContentColor = RentivoColors.ink,
      textContentColor = RentivoColors.secondaryInk,
    )
  }
}

/** One iOS `Form` section: its header followed by the card holding the section's rows. */
@Composable
private fun DemoSection(
  title: String,
  icon: ImageVector,
  content: @Composable () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = title, icon = icon)
    RentivoCard(contentPadding = PaddingValues(vertical = RentivoSpacing.tiny)) { content() }
  }
}

/**
 * A toggle row: the setting name on the left, its "Ativo"/"Inativo" state on the right. Tapping
 * anywhere flips it, mirroring the iOS `settingButton` whose whole label is the button.
 */
@Composable
private fun SettingRow(
  title: String,
  enabled: Boolean,
  testTag: String,
  onClick: () -> Unit,
) {
  val stateLabel = if (enabled) "Ativo" else "Inativo"
  val stateColor = if (enabled) RentivoColors.emerald else RentivoColors.secondaryInk

  Row(
    modifier = Modifier
      .fillMaxWidth()
      .testTag(testTag)
      .semantics { stateDescription = stateLabel }
      .clickable(onClick = onClick)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = title,
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Row(
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = if (enabled) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
        contentDescription = null,
        tint = stateColor,
        modifier = Modifier.size(18.dp),
      )
      Text(text = stateLabel, style = RentivoTypography.subheadline, color = stateColor)
    }
  }
}

/** A plain action row: an optional leading icon plus a tinted title. */
@Composable
private fun ActionRow(
  title: String,
  icon: ImageVector?,
  color: Color,
  testTag: String,
  onClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .testTag(testTag)
      .clickable(onClick = onClick)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    if (icon != null) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = color,
        modifier = Modifier.size(20.dp),
      )
    }
    Text(text = title, style = RentivoTypography.body, color = color)
  }
}
