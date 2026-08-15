package app.rentivo.features.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoLargeTopBarScaffold
import app.rentivo.designsystem.RentivoListField
import app.rentivo.designsystem.RentivoListGroup
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.TopBarChip
import app.rentivo.domain.DemoError
import app.rentivo.domain.AccountDeletionReadiness
import app.rentivo.domain.FormSubmitState
import app.rentivo.domain.LoadState
import app.rentivo.domain.ProfilePIXForm
import app.rentivo.domain.PasswordInput
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/**
 * The Rentivo website behind the "Sobre e suporte" links, mirroring the iOS
 * `LiveAPIClient.productionURL`. The API client itself is not part of this unit, so the base URL is
 * spelled out here exactly as the contract fixes it.
 */
private const val PRODUCTION_URL = "https://rentivo.com.br"

/** The minimum height of a tappable list row, i.e. the iOS 44pt hit target. */
internal val AccountRowMinHeight = 44.dp

/** The disclosure chevron: iOS draws it small and washed out, not at full secondary ink. */
private val ChevronSize = 16.dp
private const val CHEVRON_ALPHA = 0.45f

/**
 * The account root. Port of `ios/Rentivo/Features/Account/AccountView.swift`.
 *
 * Navigation is hoisted: the iOS `NavigationLink` destinations become callbacks the tab's back stack
 * pushes, so this composable stays a pure rendering of the account menu.
 */
@Composable
fun AccountView(
  onOpenProfilePix: () -> Unit,
  onOpenSecurity: () -> Unit,
  onOpenAPIKeys: () -> Unit,
  onOpenTheme: () -> Unit,
  onOpenDemoScenarios: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val uriHandler = LocalUriHandler.current
  var showDeleteAccountAlert by remember { mutableStateOf(false) }
  var deleteAccountPassword by remember { mutableStateOf("") }
  var deleteAccountValidationMessage by remember { mutableStateOf<String?>(null) }
  var deletionReadiness by remember { mutableStateOf<AccountDeletionReadiness?>(null) }
  var deletionReadinessError by remember { mutableStateOf<String?>(null) }

  LaunchedEffect(showDeleteAccountAlert) {
    if (!showDeleteAccountAlert) return@LaunchedEffect
    deletionReadiness = null
    deletionReadinessError = null
    try {
      deletionReadiness = app.dependencies.auth.accountDeletionReadiness()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      deletionReadinessError = DemoError.from(throwable).message
    }
  }

  AccountScaffold(title = "Conta", onBack = null) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      AccountSection(
        rows = listOf({
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
            horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            BrandMark(compact = true)
            Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny)) {
              Text(
                text = if (app.usesLiveAPI) "Sua conta" else "Conta de demonstração",
                style = RentivoTypography.cardTitle,
                color = RentivoColors.ink,
              )
              Text(
                text = app.currentUser.email,
                style = RentivoTypography.subheadline,
                color = RentivoColors.secondaryInk,
              )
            }
          }
        }),
      )

      AccountSection(
        title = "Perfil",
        rows = listOf(
          {
            AccountRow(
              title = "Dados e PIX",
              subtitle = "Chave e dados do recebedor",
              icon = Icons.Filled.QrCode,
              onClick = onOpenProfilePix,
            )
          },
          {
            AccountRow(
              title = "Segurança",
              subtitle = "Senha, TOTP e chaves de acesso",
              icon = Icons.Filled.Security,
              onClick = onOpenSecurity,
            )
          },
        ),
      )

      AccountSection(
        title = "Personalização e integrações",
        rows = listOf(
          {
            AccountRow(
              title = "Chaves de integração",
              subtitle = "Escopos e acessos",
              icon = Icons.Filled.VpnKey,
              onClick = onOpenAPIKeys,
            )
          },
          {
            AccountRow(
              title = "Aparência",
              subtitle = "Fontes, cores e prévia",
              icon = Icons.Filled.Palette,
              onClick = onOpenTheme,
            )
          },
        ),
      )

      if (!app.usesLiveAPI) {
        AccountSection(
          title = "Demonstração",
          rows = listOf({
            AccountRow(
              title = "Cenários do app",
              subtitle = "Atraso, falha, vazio e permissões",
              icon = Icons.Filled.Tune,
              modifier = Modifier.testTag("account.demo"),
              onClick = onOpenDemoScenarios,
            )
          }),
        )
      }

      // The website links are iOS `Link`s, not `NavigationLink`s: the title takes the accent tint
      // and the row carries no disclosure indicator, because the destination is outside the app.
      AccountSection(
        title = "Sobre e suporte",
        rows = listOf(
          {
            AccountRow(
              title = "Suporte",
              subtitle = "Fale com a gente",
              icon = Icons.AutoMirrored.Filled.Help,
              titleColor = RentivoColors.emerald,
              trailing = null,
              onClick = { uriHandler.openUri("$PRODUCTION_URL/support") },
            )
          },
          {
            AccountRow(
              title = "Política de privacidade",
              subtitle = "Como tratamos seus dados",
              icon = Icons.Filled.PanTool,
              titleColor = RentivoColors.emerald,
              trailing = null,
              onClick = { uriHandler.openUri("$PRODUCTION_URL/privacy") },
            )
          },
          {
            AccountRow(
              title = "Termos de uso",
              subtitle = "Regras do serviço",
              icon = Icons.Filled.Description,
              titleColor = RentivoColors.emerald,
              trailing = null,
              onClick = { uriHandler.openUri("$PRODUCTION_URL/terms") },
            )
          },
        ),
      )

      AccountSection(
        rows = listOf(
          {
            if (app.isSigningOut) {
              AccountTextButtonRow(
                title = "Saindo...",
                destructive = true,
                centered = true,
                enabled = false,
                loading = true,
                onClick = {},
              )
            } else {
              AccountTextButtonRow(
                title = "Sair",
                icon = Icons.AutoMirrored.Filled.Logout,
                destructive = true,
                centered = true,
                onClick = { scope.launch { app.signOut() } },
              )
            }
          },
          {
            AccountTextButtonRow(
              title = "Excluir conta",
              icon = Icons.Filled.Delete,
              destructive = true,
              centered = true,
              enabled = !app.isDeletingAccount,
              onClick = { showDeleteAccountAlert = true },
            )
          },
        ),
      )
    }
  }

  if (showDeleteAccountAlert) {
    AlertDialog(
      onDismissRequest = {
        showDeleteAccountAlert = false
        deleteAccountPassword = ""
        deleteAccountValidationMessage = null
      },
      containerColor = RentivoColors.surface,
      title = { Text(text = "Excluir sua conta?", style = RentivoTypography.title) },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          Text(
            text = "Essa ação é permanente. Suas cobranças e seus dados pessoais serão excluídos.",
            style = RentivoTypography.subheadline,
            color = RentivoColors.secondaryInk,
          )
          when {
            deletionReadinessError != null -> {
              Text(
                text = deletionReadinessError!!,
                style = RentivoTypography.subheadline,
                color = RentivoColors.destructiveText,
              )
              TextButton(
                onClick = {
                  deletionReadinessError = null
                  deletionReadiness = null
                  scope.launch {
                    try {
                      deletionReadiness = app.dependencies.auth.accountDeletionReadiness()
                    } catch (cancellation: CancellationException) {
                      throw cancellation
                    } catch (throwable: Throwable) {
                      deletionReadinessError = DemoError.from(throwable).message
                    }
                  }
                },
              ) { Text("Tentar novamente") }
            }

            deletionReadiness == null -> CircularProgressIndicator(modifier = Modifier.size(24.dp))

            deletionReadiness?.canDelete == false -> Text(
              text = deletionReadiness?.blockerMessage
                ?: "A exclusão da conta está indisponível no momento.",
              style = RentivoTypography.subheadline,
              color = RentivoColors.destructiveText,
            )

            else -> Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
              AccountPasswordField(
                label = "Senha",
                value = deleteAccountPassword,
                onValueChange = {
                  deleteAccountPassword = it
                  deleteAccountValidationMessage = null
                },
              )
              deleteAccountValidationMessage?.let { message ->
                Text(
                  text = message,
                  style = RentivoTypography.subheadline,
                  color = RentivoColors.destructiveText,
                )
              }
            }
          }
        }
      },
      confirmButton = {
        TextButton(
          onClick = {
            PasswordInput.validationMessage(deleteAccountPassword)?.let { message ->
              deleteAccountValidationMessage = message
              return@TextButton
            }
            // Capture before clearing: the field is reset synchronously so the password never
            // survives the dialog, exactly like the iOS alert action does.
            val password = deleteAccountPassword
            deleteAccountPassword = ""
            showDeleteAccountAlert = false
            scope.launch { app.deleteAccount(password = password) }
          },
          enabled = deletionReadiness?.canDelete == true &&
            deleteAccountPassword.isNotEmpty() &&
            !app.isDeletingAccount,
        ) {
          Text(text = "Excluir conta", color = RentivoColors.destructiveText)
        }
      },
      dismissButton = {
        TextButton(
          onClick = {
            deleteAccountPassword = ""
            deleteAccountValidationMessage = null
            showDeleteAccountAlert = false
          },
        ) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
    )
  }
}

/**
 * "Dados e PIX". Port of the iOS `ProfilePixView`.
 *
 * The three PIX fields are the personal receiver identity every personal billing without its own
 * PIX inherits.
 */
@Composable
fun ProfilePixView(onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var form by remember { mutableStateOf(ProfilePIXForm.from()) }
  var submitState by remember { mutableStateOf(FormSubmitState.idle) }
  var loadState by remember { mutableStateOf<LoadState<ProfilePIXForm>>(LoadState.Loading) }

  // Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is connected to the
  // live API, the signed-in user owns their own account and this screen should be fully enabled
  // regardless of the demo viewer-mode toggle.
  val isDemoViewerLocked = !app.usesLiveAPI && app.demoSettings.viewerMode

  suspend fun load() {
    loadState = LoadState.Loading
    try {
      form = ProfilePIXForm.from(app.loadProfile())
      loadState = LoadState.Loaded(form)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      loadState = LoadState.Failed(DemoError.from(throwable))
    }
  }

  LaunchedEffect(Unit) { load() }

  AccountScaffold(
    title = "Dados e PIX",
    onBack = onBack,
    actions = {
      if (!isDemoViewerLocked) {
        AccountToolbarAction {
          TextButton(
            onClick = {
              scope.launch {
                if (submitState.isSubmitting) return@launch
                submitState = submitState.start()
                try {
                  val clearing = form.configuration == null
                  form = ProfilePIXForm.from(app.updateProfilePIX(form.configuration))
                  loadState = LoadState.Loaded(form)
                  app.showNotice(if (clearing) "PIX pessoal removido." else "PIX pessoal atualizado.")
                } catch (cancellation: CancellationException) {
                  throw cancellation
                } catch (throwable: Throwable) {
                  app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
                } finally {
                  submitState = submitState.finish()
                }
              }
            },
            enabled = loadState is LoadState.Loaded && form.isSavable && !submitState.isSubmitting,
            modifier = Modifier.testTag("profile.pix.save"),
          ) {
            Text(text = "Salvar", color = RentivoColors.emerald)
          }
        }
      }
    },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
      PageStateView(state = loadState, retry = { scope.launch { load() } }) {
        Column(
          modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(RentivoSpacing.page),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
        ) {
      AccountSection(
        title = "Conta",
        rows = listOf(
          { AccountLabeledRow(label = "E-mail", value = app.currentUser.email) },
          {
            AccountLabeledRow(
              label = "Ambiente",
              value = if (app.usesLiveAPI) "Rentivo" else "Demonstração local",
            )
          },
        ),
      )

      // iOS renders these as plain `TextField`s in a `Form`: the PT-BR label is the placeholder,
      // and the typed value replaces it. There is no notched outline and no floating label.
      AccountSection(
        title = "PIX pessoal",
        rows = listOf(
          {
            AccountFieldRow(
              placeholder = "Chave PIX",
              value = form.key,
              onValueChange = { form = form.copy(key = it) },
              enabled = !isDemoViewerLocked,
              keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
          },
          {
            AccountFieldRow(
              placeholder = "Nome do recebedor",
              value = form.merchantName,
              onValueChange = { form = form.copy(merchantName = it) },
              enabled = !isDemoViewerLocked,
            )
          },
          {
            AccountFieldRow(
              placeholder = "Cidade",
              value = form.merchantCity,
              onValueChange = { form = form.copy(merchantCity = it) },
              enabled = !isDemoViewerLocked,
              keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
          },
        ),
      )

      AccountSection(
        rows = listOf({
          AccountFootnote(
            text = "Cobranças pessoais sem PIX próprio herdam esta configuração.",
            icon = Icons.AutoMirrored.Filled.CallSplit,
          )
        }),
      )
        }
      }
    }
  }
}

/**
 * The chrome every account screen shares: the paper page, a large PT-BR navigation title that
 * collapses as the screen scrolls, and an optional back chevron sitting in the iOS 26 toolbar chip.
 */
@Composable
internal fun AccountScaffold(
  title: String,
  onBack: (() -> Unit)?,
  modifier: Modifier = Modifier,
  actions: @Composable RowScope.() -> Unit = {},
  content: @Composable (PaddingValues) -> Unit,
) {
  RentivoLargeTopBarScaffold(
    title = title,
    modifier = modifier,
    navigationIcon = onBack?.let { back ->
      {
        TopBarChip {
          IconButton(onClick = back) {
            Icon(
              imageVector = Icons.AutoMirrored.Filled.ArrowBack,
              contentDescription = "Voltar",
              tint = RentivoColors.ink,
            )
          }
        }
      }
    },
    actions = actions,
    content = content,
  )
}

/**
 * A trailing toolbar control of an [AccountScaffold]: the same circular chip the back chevron sits
 * in, held off the trailing edge so it does not touch the screen border.
 */
@Composable
internal fun AccountToolbarAction(content: @Composable () -> Unit) {
  Box(modifier = Modifier.padding(end = RentivoSpacing.small)) {
    TopBarChip(content = content)
  }
}

/**
 * One iOS `Section`: an optional gray header, an inset-grouped white plate holding the rows, and an
 * optional footer sentence underneath it.
 *
 * Rows are passed as a list rather than as a slot so [RentivoListGroup] can place the hairlines
 * itself; build the list with `buildList` when a row is conditional.
 */
@Composable
internal fun AccountSection(
  rows: List<@Composable () -> Unit>,
  modifier: Modifier = Modifier,
  title: String? = null,
  footer: String? = null,
) {
  Column(
    modifier = modifier,
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
  ) {
    if (title != null) {
      Text(
        text = title,
        style = RentivoTypography.metadata,
        color = RentivoColors.secondaryInk,
      )
    }
    RentivoListGroup(rows = rows)
    if (footer != null) {
      Text(
        text = footer,
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
  }
}

/**
 * A menu row: emerald leading symbol, title, caption subtitle and — for rows that push a screen — a
 * small, washed-out disclosure chevron.
 *
 * [titleColor] carries the accent tint an iOS `Link` gives its label; pass `trailing = null`
 * alongside it, because a `Link` shows no disclosure indicator.
 */
@Composable
internal fun AccountRow(
  title: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  subtitle: String? = null,
  titleColor: Color = RentivoColors.ink,
  titleStyle: TextStyle = RentivoTypography.cardTitle,
  trailing: ImageVector? = Icons.Filled.ChevronRight,
  onClick: () -> Unit,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.emerald)
    Column(
      modifier = Modifier.weight(1f),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
    ) {
      Text(text = title, style = titleStyle, color = titleColor)
      if (subtitle != null) {
        Text(text = subtitle, style = RentivoTypography.caption, color = RentivoColors.secondaryInk)
      }
    }
    if (trailing != null) {
      Icon(
        imageVector = trailing,
        contentDescription = null,
        tint = RentivoColors.secondaryInk.copy(alpha = CHEVRON_ALPHA),
        modifier = Modifier.size(ChevronSize),
      )
    }
  }
}

/** The iOS `LabeledContent`: a label on the left, its read-only value on the right. */
@Composable
internal fun AccountLabeledRow(
  label: String,
  value: String,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = label,
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Text(text = value, style = RentivoTypography.subheadline, color = RentivoColors.secondaryInk)
  }
}

/**
 * A borderless text field filling one row of a section, the way an iOS `TextField` sits directly on
 * a `Form` row: the label is the placeholder, and nothing outlines the field.
 */
@Composable
internal fun AccountFieldRow(
  placeholder: String,
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  monospace: Boolean = false,
  keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
  visualTransformation: VisualTransformation = VisualTransformation.None,
) {
  Box(
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    contentAlignment = Alignment.CenterStart,
  ) {
    RentivoListField(
      value = value,
      onValueChange = onValueChange,
      placeholder = placeholder,
      enabled = enabled,
      monospace = monospace,
      keyboardOptions = keyboardOptions,
      visualTransformation = visualTransformation,
    )
  }
}

/**
 * A text action occupying a whole row of a section: the platform red when it destroys something,
 * emerald otherwise, always at body weight like an iOS `Button` inside a `List`.
 *
 * [centered] mirrors the `.frame(maxWidth: .infinity)` iOS puts on the account-level actions, and
 * [loading] swaps the leading symbol for a spinner while the action is in flight.
 */
@Composable
internal fun AccountTextButtonRow(
  title: String,
  modifier: Modifier = Modifier,
  icon: ImageVector? = null,
  destructive: Boolean = false,
  enabled: Boolean = true,
  centered: Boolean = false,
  loading: Boolean = false,
  onClick: () -> Unit,
) {
  val color = when {
    !enabled -> RentivoColors.secondaryInk
    destructive -> RentivoColors.destructiveText
    else -> RentivoColors.emerald
  }
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clickable(enabled = enabled, onClick = onClick)
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(
      space = RentivoSpacing.small,
      alignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
    ),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    if (loading) {
      CircularProgressIndicator(
        modifier = Modifier.size(18.dp),
        color = color,
        strokeWidth = 2.dp,
      )
    } else if (icon != null) {
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

/** Small explanatory copy, optionally introduced by a symbol like the iOS `Label` footnotes. */
@Composable
internal fun AccountFootnote(
  text: String,
  modifier: Modifier = Modifier,
  icon: ImageVector? = null,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    if (icon != null) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = RentivoColors.emerald,
        modifier = Modifier.size(18.dp),
      )
    }
    Text(
      text = text,
      style = RentivoTypography.caption,
      color = RentivoColors.secondaryInk,
      modifier = Modifier.weight(1f),
    )
  }
}

/** The masked field every password-collecting dialog on this tab reuses. */
@Composable
internal fun AccountPasswordField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  OutlinedTextField(
    value = value,
    onValueChange = onValueChange,
    label = { Text(text = label) },
    singleLine = true,
    visualTransformation = PasswordVisualTransformation(),
    modifier = modifier.fillMaxWidth(),
  )
}
