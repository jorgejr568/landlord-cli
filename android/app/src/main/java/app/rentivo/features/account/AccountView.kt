package app.rentivo.features.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.domain.DemoError
import app.rentivo.domain.ProfilePIXForm
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/**
 * The Rentivo website behind the "Sobre e suporte" links, mirroring the iOS
 * `LiveAPIClient.productionURL`. The API client itself is not part of this unit, so the base URL is
 * spelled out here exactly as the contract fixes it.
 */
private const val PRODUCTION_URL = "https://rentivo.com.br"

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

  AccountScaffold(title = "Conta", onBack = null) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      RentivoCard {
        Row(
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
      }

      AccountSection(title = "Perfil") {
        AccountRow(
          title = "Dados e PIX",
          subtitle = "Chave e dados do recebedor",
          icon = Icons.Filled.QrCode,
          onClick = onOpenProfilePix,
        )
        AccountRow(
          title = "Segurança",
          subtitle = "Senha, TOTP e chaves de acesso",
          icon = Icons.Filled.Security,
          onClick = onOpenSecurity,
        )
      }

      AccountSection(title = "Personalização e integrações") {
        AccountRow(
          title = "Chaves de integração",
          subtitle = "Escopos e acessos",
          icon = Icons.Filled.VpnKey,
          onClick = onOpenAPIKeys,
        )
        AccountRow(
          title = "Aparência",
          subtitle = "Fontes, cores e prévia",
          icon = Icons.Filled.Palette,
          onClick = onOpenTheme,
        )
      }

      if (!app.usesLiveAPI) {
        AccountSection(title = "Demonstração") {
          AccountRow(
            title = "Cenários do app",
            subtitle = "Atraso, falha, vazio e permissões",
            icon = Icons.Filled.Tune,
            modifier = Modifier.testTag("account.demo"),
            onClick = onOpenDemoScenarios,
          )
        }
      }

      AccountSection(title = "Sobre e suporte") {
        AccountRow(
          title = "Suporte",
          subtitle = "Fale com a gente",
          icon = Icons.AutoMirrored.Filled.HelpOutline,
          trailing = Icons.AutoMirrored.Filled.OpenInNew,
          onClick = { uriHandler.openUri("$PRODUCTION_URL/support") },
        )
        AccountRow(
          title = "Política de privacidade",
          subtitle = "Como tratamos seus dados",
          icon = Icons.Filled.PrivacyTip,
          trailing = Icons.AutoMirrored.Filled.OpenInNew,
          onClick = { uriHandler.openUri("$PRODUCTION_URL/privacy") },
        )
        AccountRow(
          title = "Termos de uso",
          subtitle = "Regras do serviço",
          icon = Icons.Filled.Description,
          trailing = Icons.AutoMirrored.Filled.OpenInNew,
          onClick = { uriHandler.openUri("$PRODUCTION_URL/terms") },
        )
      }

      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        RentivoButton(
          onClick = { scope.launch { app.signOut() } },
          color = RentivoColors.coral,
          enabled = !app.isSigningOut,
        ) {
          if (app.isSigningOut) {
            CircularProgressIndicator(
              modifier = Modifier.size(18.dp),
              color = Color.White,
              strokeWidth = 2.dp,
            )
            Spacer(modifier = Modifier.width(RentivoSpacing.small))
            Text(text = "Saindo...", style = RentivoTypography.cardTitle, color = Color.White)
          } else {
            Icon(
              imageVector = Icons.AutoMirrored.Filled.Logout,
              contentDescription = null,
              tint = Color.White,
            )
            Spacer(modifier = Modifier.width(RentivoSpacing.small))
            Text(text = "Sair", style = RentivoTypography.cardTitle, color = Color.White)
          }
        }

        RentivoButton(
          onClick = { showDeleteAccountAlert = true },
          color = RentivoColors.coral,
          enabled = !app.isDeletingAccount,
        ) {
          Icon(
            imageVector = Icons.Filled.Delete,
            contentDescription = null,
            tint = Color.White,
          )
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
          Text(text = "Excluir conta", style = RentivoTypography.cardTitle, color = Color.White)
        }
      }
    }
  }

  if (showDeleteAccountAlert) {
    AlertDialog(
      onDismissRequest = {
        showDeleteAccountAlert = false
        deleteAccountPassword = ""
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
          AccountPasswordField(
            label = "Senha",
            value = deleteAccountPassword,
            onValueChange = { deleteAccountPassword = it },
          )
        }
      },
      confirmButton = {
        TextButton(
          onClick = {
            // Capture before clearing: the field is reset synchronously so the password never
            // survives the dialog, exactly like the iOS alert action does.
            val password = deleteAccountPassword
            deleteAccountPassword = ""
            showDeleteAccountAlert = false
            scope.launch { app.deleteAccount(password = password) }
          },
        ) {
          Text(text = "Excluir conta", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(
          onClick = {
            deleteAccountPassword = ""
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

  // Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is connected to the
  // live API, the signed-in user owns their own account and this screen should be fully enabled
  // regardless of the demo viewer-mode toggle.
  val isDemoViewerLocked = !app.usesLiveAPI && app.demoSettings.viewerMode

  LaunchedEffect(Unit) {
    try {
      form = ProfilePIXForm.from(app.loadProfile())
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  AccountScaffold(
    title = "Dados e PIX",
    onBack = onBack,
    actions = {
      if (!isDemoViewerLocked) {
        TextButton(
          onClick = {
            scope.launch {
              try {
                form = ProfilePIXForm.from(app.updateProfilePIX(form.configuration))
                app.showNotice("PIX pessoal atualizado.")
              } catch (cancellation: CancellationException) {
                throw cancellation
              } catch (throwable: Throwable) {
                app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
              }
            }
          },
          enabled = form.configuration.isComplete,
          modifier = Modifier.testTag("profile.pix.save"),
        ) {
          Text(text = "Salvar", color = RentivoColors.emerald)
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
      AccountSection(title = "Conta") {
        AccountLabeledRow(label = "E-mail", value = app.currentUser.email)
        AccountLabeledRow(
          label = "Ambiente",
          value = if (app.usesLiveAPI) "Rentivo" else "Demonstração local",
        )
      }

      AccountSection(title = "PIX pessoal") {
        Column(
          modifier = Modifier.padding(
            horizontal = RentivoSpacing.large,
            vertical = RentivoSpacing.small,
          ),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
        ) {
          OutlinedTextField(
            value = form.key,
            onValueChange = { form = form.copy(key = it) },
            label = { Text(text = "Chave PIX") },
            enabled = !isDemoViewerLocked,
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            modifier = Modifier.fillMaxWidth(),
          )
          OutlinedTextField(
            value = form.merchantName,
            onValueChange = { form = form.copy(merchantName = it) },
            label = { Text(text = "Nome do recebedor") },
            enabled = !isDemoViewerLocked,
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
          )
          OutlinedTextField(
            value = form.merchantCity,
            onValueChange = { form = form.copy(merchantCity = it) },
            label = { Text(text = "Cidade") },
            enabled = !isDemoViewerLocked,
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            modifier = Modifier.fillMaxWidth(),
          )
        }
      }

      AccountSection {
        AccountFootnote(
          text = "Cobranças pessoais sem PIX próprio herdam esta configuração.",
          icon = Icons.Filled.AccountTree,
        )
      }
    }
  }
}

/** The chrome every account screen shares: paper background, PT-BR title, optional back arrow. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountScaffold(
  title: String,
  onBack: (() -> Unit)?,
  modifier: Modifier = Modifier,
  actions: @Composable RowScope.() -> Unit = {},
  content: @Composable (PaddingValues) -> Unit,
) {
  Scaffold(
    modifier = modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = {
          Text(text = title, style = RentivoTypography.title, color = RentivoColors.ink)
        },
        navigationIcon = {
          if (onBack != null) {
            IconButton(onClick = onBack) {
              Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Voltar",
                tint = RentivoColors.ink,
              )
            }
          }
        },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(containerColor = RentivoColors.paper),
      )
    },
    content = content,
  )
}

/** One iOS `Section`: an optional header above a card holding the section's rows. */
@Composable
internal fun AccountSection(
  title: String? = null,
  modifier: Modifier = Modifier,
  content: @Composable ColumnScope.() -> Unit,
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
    RentivoCard(contentPadding = PaddingValues(vertical = RentivoSpacing.small), content = content)
  }
}

/**
 * A menu row: emerald leading symbol, title, caption subtitle and a trailing affordance —
 * [Icons.Filled.ChevronRight] for pushes, an external-link glyph for the website links.
 */
@Composable
internal fun AccountRow(
  title: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  subtitle: String? = null,
  trailing: ImageVector? = Icons.Filled.ChevronRight,
  onClick: () -> Unit,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.emerald)
    Column(
      modifier = Modifier.weight(1f),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
    ) {
      Text(text = title, style = RentivoTypography.cardTitle, color = RentivoColors.ink)
      if (subtitle != null) {
        Text(text = subtitle, style = RentivoTypography.caption, color = RentivoColors.secondaryInk)
      }
    }
    if (trailing != null) {
      Icon(
        imageVector = trailing,
        contentDescription = null,
        tint = RentivoColors.secondaryInk,
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

/** A full-width text action inside a section card, coral when it destroys something. */
@Composable
internal fun AccountTextButtonRow(
  title: String,
  modifier: Modifier = Modifier,
  destructive: Boolean = false,
  onClick: () -> Unit,
) {
  Text(
    text = title,
    style = RentivoTypography.cardTitle,
    color = if (destructive) RentivoColors.coral else RentivoColors.emerald,
    modifier = modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
  )
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
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    if (icon != null) {
      Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.secondaryInk)
    }
    Text(
      text = text,
      style = RentivoTypography.caption,
      color = RentivoColors.secondaryInk,
      modifier = Modifier.weight(1f),
    )
  }
}

/** The masked field every password-collecting dialog and form on this tab reuses. */
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
