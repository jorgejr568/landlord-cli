package app.rentivo.features.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.domain.DemoError
import app.rentivo.domain.LoadState
import app.rentivo.domain.Passkey
import app.rentivo.domain.SecuritySummary
import app.rentivo.domain.TOTPEnrollment
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/**
 * "Segurança". Port of `ios/Rentivo/Features/Account/SecurityViews.swift`.
 *
 * Every load blanks the screen back to `Loading`: the summary decides which two-factor actions are
 * offered at all, so leaving stale controls up during a refresh would invite the user to act on a
 * state the server no longer has.
 *
 * Passkeys are read/delete only. Registering one needs a WebAuthn ceremony the app deliberately
 * does not implement, so the always-visible footnote sends the user to the website instead.
 */
@Composable
fun SecurityView(onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var state by remember { mutableStateOf<LoadState<SecuritySummary>>(LoadState.Idle) }
  var recoveryCodes by remember { mutableStateOf(emptyList<String>()) }
  var showingRecoveryCodes by remember { mutableStateOf(false) }
  var enrollment by remember { mutableStateOf<TOTPEnrollment?>(null) }
  var showingDisableTOTP by remember { mutableStateOf(false) }
  var password by remember { mutableStateOf("") }
  var passkeyPendingDelete by remember { mutableStateOf<Passkey?>(null) }
  var changingPassword by remember { mutableStateOf(false) }

  // Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is connected to the
  // live API, the signed-in user owns their own account and this screen should be fully enabled
  // regardless of the demo viewer-mode toggle.
  val isDemoViewerLocked = !app.usesLiveAPI && app.demoSettings.viewerMode

  suspend fun load() {
    state = LoadState.Loading
    state = try {
      LoadState.Loaded(app.dependencies.security.securitySummary())
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      LoadState.Failed(DemoError.from(throwable))
    }
  }

  /** Every mutation on this screen reports failure the same way: a warning notice, no state change. */
  suspend fun warnOnFailure(operation: suspend () -> Unit) {
    try {
      operation()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  if (changingPassword) {
    ChangePasswordView(onBack = { changingPassword = false })
    return
  }

  AccountScaffold(title = "Segurança", onBack = onBack) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
      PageStateView(state = state, retry = { scope.launch { load() } }) { summary ->
        Column(
          modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(RentivoSpacing.page),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
        ) {
          AccountSection(
            title = "Senha",
            rows = listOf({
              AccountRow(
                title = "Alterar senha",
                icon = Icons.Filled.VpnKey,
                titleStyle = RentivoTypography.body,
                onClick = { changingPassword = true },
              )
            }),
          )

          AccountSection(
            title = "Autenticação em duas etapas",
            rows = buildList {
              add({
                AccountLabeledRow(
                  label = "Aplicativo autenticador",
                  value = if (summary.totpEnabled) "Ativado" else "Desativado",
                )
              })
              if (!isDemoViewerLocked) {
                if (summary.totpEnabled) {
                  add({
                    AccountTextButtonRow(
                      title = "Desativar",
                      destructive = true,
                      onClick = { showingDisableTOTP = true },
                    )
                  })
                } else {
                  add({
                    AccountTextButtonRow(
                      title = "Configurar aplicativo autenticador",
                      onClick = {
                        scope.launch {
                          warnOnFailure {
                            enrollment = app.dependencies.security.beginTOTPEnrollment()
                          }
                        }
                      },
                    )
                  })
                }
                add({
                  AccountTextButtonRow(
                    title = "Gerar novos códigos de recuperação",
                    onClick = {
                      scope.launch {
                        warnOnFailure {
                          recoveryCodes = app.dependencies.security.regenerateRecoveryCodes()
                          load()
                          showingRecoveryCodes = true
                        }
                      }
                    },
                  )
                })
              }
              add({
                AccountLabeledRow(
                  label = "Códigos disponíveis",
                  value = "${summary.recoveryCodeCount}",
                )
              })
            },
          )

          AccountSection(
            title = "Chaves de acesso",
            rows = buildList {
              if (summary.passkeys.isEmpty()) {
                add({ AccountFootnote(text = "Nenhuma chave de acesso registrada ainda.") })
              } else {
                summary.passkeys.forEach { passkey ->
                  add({
                    PasskeyRow(
                      passkey = passkey,
                      canDelete = !isDemoViewerLocked,
                      onDelete = { passkeyPendingDelete = passkey },
                    )
                  })
                }
              }
              add({
                AccountFootnote(
                  text = "Para registrar uma nova chave de acesso, entre pelo navegador do " +
                    "Rentivo. Ela ficará disponível automaticamente neste aplicativo.",
                )
              })
            },
          )
        }
      }
    }
  }

  if (showingRecoveryCodes) {
    RecoveryCodeView(codes = recoveryCodes, onDismiss = { showingRecoveryCodes = false })
  }

  enrollment?.let { pending ->
    TOTPEnrollmentView(
      enrollment = pending,
      onDismiss = { enrollment = null },
      onConfirm = { code ->
        warnOnFailure {
          recoveryCodes = app.dependencies.security.confirmTOTPEnrollment(code = code)
          enrollment = null
          load()
          showingRecoveryCodes = true
        }
      },
    )
  }

  if (showingDisableTOTP) {
    AlertDialog(
      onDismissRequest = {
        showingDisableTOTP = false
        password = ""
      },
      containerColor = RentivoColors.surface,
      title = {
        Text(text = "Desativar autenticação em duas etapas", style = RentivoTypography.title)
      },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          Text(
            text = "Confirme sua senha para desativar o aplicativo autenticador.",
            style = RentivoTypography.subheadline,
            color = RentivoColors.secondaryInk,
          )
          AccountPasswordField(
            label = "Senha atual",
            value = password,
            onValueChange = { password = it },
          )
        }
      },
      confirmButton = {
        TextButton(
          onClick = {
            showingDisableTOTP = false
            scope.launch {
              warnOnFailure {
                app.dependencies.security.disableTOTP(password = password)
                password = ""
                load()
              }
            }
          },
        ) {
          Text(text = "Desativar", color = RentivoColors.destructiveText)
        }
      },
      dismissButton = {
        TextButton(
          onClick = {
            showingDisableTOTP = false
            password = ""
          },
        ) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
    )
  }

  passkeyPendingDelete?.let { passkey ->
    AlertDialog(
      onDismissRequest = { passkeyPendingDelete = null },
      containerColor = RentivoColors.surface,
      title = { Text(text = "Excluir esta chave de acesso?", style = RentivoTypography.title) },
      text = {
        Text(
          text = "\"${passkey.name}\" não poderá mais ser usada para entrar neste dispositivo. " +
            "Esta ação não pode ser desfeita.",
          style = RentivoTypography.subheadline,
          color = RentivoColors.secondaryInk,
        )
      },
      confirmButton = {
        TextButton(
          onClick = {
            passkeyPendingDelete = null
            scope.launch {
              warnOnFailure {
                app.dependencies.security.deletePasskey(id = passkey.id)
                load()
              }
            }
          },
          modifier = Modifier.testTag("security.passkey.delete.confirm"),
        ) {
          Text(text = "Excluir chave de acesso", color = RentivoColors.destructiveText)
        }
      },
      dismissButton = {
        TextButton(
          onClick = { passkeyPendingDelete = null },
          modifier = Modifier.testTag("security.passkey.delete.cancel"),
        ) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
    )
  }
}

@Composable
private fun PasskeyRow(
  passkey: Passkey,
  canDelete: Boolean,
  onDelete: () -> Unit,
) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
  ) {
    Text(text = passkey.name, style = RentivoTypography.cardTitle, color = RentivoColors.ink)
    val lastUsed = passkey.lastUsedAt?.formattedPTBR(time = PTBRTimeStyle.SHORTENED) ?: "nunca"
    Text(
      text = "Último uso: $lastUsed",
      style = RentivoTypography.caption,
      color = RentivoColors.secondaryInk,
    )
    if (canDelete) {
      Text(
        text = "Excluir",
        style = RentivoTypography.metadata,
        color = RentivoColors.destructiveText,
        modifier = Modifier
          .testTag("security.passkey.delete")
          .clickable(onClick = onDelete),
      )
    }
  }
}

/** "Senha". Pushed over [SecurityView], which owns this leg of the account back stack. */
@Composable
private fun ChangePasswordView(onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var currentPassword by remember { mutableStateOf("") }
  var newPassword by remember { mutableStateOf("") }
  var confirmPassword by remember { mutableStateOf("") }
  var isSaving by remember { mutableStateOf(false) }
  var validationMessage by remember { mutableStateOf<String?>(null) }

  BackHandler(onBack = onBack)

  fun save() {
    // The client-side mismatch check short-circuits the request; every other failure is the
    // server's verdict, rendered in the same coral label.
    if (newPassword != confirmPassword) {
      validationMessage = "As senhas não coincidem."
      return
    }
    validationMessage = null
    isSaving = true
    scope.launch {
      try {
        app.dependencies.security.changePassword(
          currentPassword = currentPassword,
          newPassword = newPassword,
          confirmPassword = confirmPassword,
        )
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        app.showNotice("Senha alterada com sucesso.")
        onBack()
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        validationMessage = DemoError.from(throwable).message
      } finally {
        isSaving = false
      }
    }
  }

  AccountScaffold(title = "Senha", onBack = onBack) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      AccountSection(
        title = "Alterar senha",
        footer = "Use uma senha forte e exclusiva para sua conta Rentivo.",
        rows = listOf(
          {
            AccountFieldRow(
              placeholder = "Senha atual",
              value = currentPassword,
              onValueChange = { currentPassword = it },
              visualTransformation = PasswordVisualTransformation(),
            )
          },
          {
            AccountFieldRow(
              placeholder = "Nova senha",
              value = newPassword,
              onValueChange = { newPassword = it },
              visualTransformation = PasswordVisualTransformation(),
            )
          },
          {
            AccountFieldRow(
              placeholder = "Confirmar nova senha",
              value = confirmPassword,
              onValueChange = { confirmPassword = it },
              visualTransformation = PasswordVisualTransformation(),
            )
          },
        ),
      )

      validationMessage?.let { message ->
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Icon(
            imageVector = Icons.Filled.Error,
            contentDescription = null,
            tint = RentivoColors.coral,
          )
          Text(text = message, style = RentivoTypography.subheadline, color = RentivoColors.coral)
        }
      }

      RentivoButton(
        text = "Salvar nova senha",
        onClick = ::save,
        enabled = !isSaving &&
          currentPassword.isNotEmpty() &&
          newPassword.isNotEmpty() &&
          confirmPassword.isNotEmpty(),
      )
    }
  }
}

/** The one-time recovery codes, shown as a full-screen sheet over [SecurityView]. */
@Composable
private fun RecoveryCodeView(codes: List<String>, onDismiss: () -> Unit) {
  AccountSheet(
    title = "Recuperação",
    actionTitle = "Concluir",
    onAction = onDismiss,
    onDismiss = onDismiss,
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large)) {
      SheetHeader(title = "Códigos de recuperação", icon = Icons.Filled.Shield)
      Text(
        text = "Guarde estes códigos em local seguro. Eles aparecem uma única vez.",
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
      // Two fixed columns, like the iOS LazyVGrid; a trailing odd code keeps its own half.
      codes.chunked(2).forEach { pair ->
        Row(horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          pair.forEach { code ->
            Text(
              text = code,
              style = MonospacedCode,
              color = RentivoColors.ink,
              modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(10.dp))
                .background(RentivoColors.surface)
                .padding(RentivoSpacing.medium),
            )
          }
          if (pair.size == 1) Box(modifier = Modifier.weight(1f))
        }
      }
    }
  }
}

/**
 * The TOTP enrollment sheet.
 *
 * `enrollment.qrCodeBase64` is deliberately not rendered: enrollment here is manual-entry only, so
 * the user types the secret into their authenticator instead of the app painting a scannable image
 * of its own credential on screen.
 */
@Composable
private fun TOTPEnrollmentView(
  enrollment: TOTPEnrollment,
  onDismiss: () -> Unit,
  onConfirm: suspend (String) -> Unit,
) {
  val scope = rememberCoroutineScope()
  var code by remember { mutableStateOf("") }

  AccountSheet(
    title = "Autenticador",
    actionTitle = "Cancelar",
    onAction = onDismiss,
    onDismiss = onDismiss,
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large)) {
      SheetHeader(title = "Configure seu autenticador", icon = Icons.Filled.QrCode)
      Text(
        text = "Adicione esta chave manualmente ao seu aplicativo autenticador e informe o " +
          "código de seis dígitos.",
        style = RentivoTypography.body,
        color = RentivoColors.ink,
      )
      SelectionContainer {
        Text(
          text = enrollment.secret,
          style = MonospacedCode,
          color = RentivoColors.ink,
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(RentivoColors.surface)
            .padding(RentivoSpacing.medium),
        )
      }
      OutlinedTextField(
        value = code,
        onValueChange = { code = it },
        label = { Text(text = "Código do autenticador") },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier.fillMaxWidth(),
      )
      RentivoButton(
        text = "Confirmar",
        onClick = { scope.launch { onConfirm(code) } },
        enabled = code.isNotBlank(),
      )
    }
  }
}

@Composable
private fun SheetHeader(title: String, icon: ImageVector) {
  Row(
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.ink)
    Text(text = title, style = RentivoTypography.title, color = RentivoColors.ink)
  }
}

/**
 * The iOS `.sheet`: a full-screen surface rising over everything, including the tab bar, with page
 * chrome and a single trailing toolbar action.
 *
 * The sheet's own layer already sits below the status bar, so the scaffold inside it must not add
 * that inset a second time — hence the explicit consumption.
 */
@Composable
private fun AccountSheet(
  title: String,
  actionTitle: String,
  onAction: () -> Unit,
  onDismiss: () -> Unit,
  content: @Composable () -> Unit,
) {
  FullScreenSheet(onDismissRequest = onDismiss) {
    AccountScaffold(
      title = title,
      onBack = null,
      modifier = Modifier.consumeWindowInsets(WindowInsets.statusBars),
      actions = {
        TextButton(onClick = onAction) {
          Text(text = actionTitle, color = RentivoColors.emerald)
        }
      },
    ) { padding ->
      Column(
        modifier = Modifier
          .fillMaxSize()
          .padding(padding)
          .verticalScroll(rememberScrollState())
          .padding(RentivoSpacing.page),
      ) {
        content()
      }
    }
  }
}

/** Bold monospace, for secrets and recovery codes that get transcribed character by character. */
private val MonospacedCode = RentivoTypography.body.copy(
  fontFamily = FontFamily.Monospace,
  fontWeight = FontWeight.Bold,
)

/** Time precision of [formattedPTBR], mirroring the iOS `Date.FormatStyle.TimeStyle` cases used. */
enum class PTBRTimeStyle {
  OMITTED,
  SHORTENED,
}

private val PTBRLocale: Locale = Locale.forLanguageTag("pt-BR")

/**
 * Formats this instant pinned to the pt-BR locale, so PT-BR sentences never leak a device-locale
 * date string (e.g. "Jul 23, 2026" showing up on an en-US device inside otherwise-Portuguese copy).
 */
fun Instant.formattedPTBR(time: PTBRTimeStyle = PTBRTimeStyle.OMITTED): String {
  val formatter = when (time) {
    PTBRTimeStyle.OMITTED -> DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
    PTBRTimeStyle.SHORTENED ->
      DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
  }
  return formatter.withLocale(PTBRLocale).withZone(ZoneId.systemDefault()).format(this)
}
