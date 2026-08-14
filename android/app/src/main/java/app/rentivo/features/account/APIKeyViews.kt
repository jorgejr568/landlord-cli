package app.rentivo.features.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.GppMaybe
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoLargeTopBarScaffold
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.TopBarChip
import app.rentivo.designsystem.ptBRCount
import app.rentivo.designsystem.rentivoSwitchColors
import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.APIKeyGrantEditRule
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.APIKeyNameRule
import app.rentivo.domain.APIKeyOptions
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.APIKeyScopeEditRule
import app.rentivo.domain.CreatedAPIKeySecret
import app.rentivo.domain.DemoError
import app.rentivo.domain.FormSubmitState
import app.rentivo.domain.LoadState
import app.rentivo.domain.Organization
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant

/** One year in seconds — the default validity a freshly drafted key gets. */
private const val DEFAULT_VALIDITY_SECONDS = 31_536_000L

/** A `Switch` at iOS `UISwitch` proportions: Material draws its own noticeably larger. */
private const val SWITCH_SCALE = 0.85f

/**
 * The integration-key list. Port of `APIKeyListView` in
 * `ios/Rentivo/Features/Account/APIKeyViews.swift`.
 *
 * This is one of the screens that always blanks to `Loading` on refresh: the key list is short,
 * and a stale list of credentials is worse than a spinner.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun APIKeyListScreen(onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var state by remember { mutableStateOf<LoadState<List<APIKeyMetadata>>>(LoadState.Idle) }
  var showingCreate by remember { mutableStateOf(false) }
  var createdSecret by remember { mutableStateOf<CreatedAPIKeySecret?>(null) }
  var editingKey by remember { mutableStateOf<APIKeyMetadata?>(null) }
  var keyPendingRevoke by remember { mutableStateOf<APIKeyMetadata?>(null) }
  var isRefreshing by remember { mutableStateOf(false) }

  // Demo "viewer mode" is a local demo/mock-backend concept only. Once the app is connected to the
  // live API, the signed-in user owns their own account and this screen should be fully enabled
  // regardless of the demo viewer-mode toggle.
  val isDemoViewerLocked = !app.usesLiveAPI && app.demoSettings.viewerMode
  val canCreate = !isDemoViewerLocked

  suspend fun load() {
    state = LoadState.Loading
    state = try {
      val keys = app.dependencies.apiKeys.listAPIKeys()
      if (keys.isEmpty()) LoadState.Empty else LoadState.Loaded(keys)
    } catch (cancellation: CancellationException) {
      // A superseded load (the screen went away, or `dataRevision` restarted this effect) must not
      // stomp the fresh state with a stale `Failed`.
      throw cancellation
    } catch (error: Throwable) {
      LoadState.Failed(DemoError.from(error))
    }
  }

  suspend fun revoke(key: APIKeyMetadata) {
    try {
      app.dependencies.apiKeys.revokeAPIKey(key.id)
      load()
      app.showNotice("Chave revogada.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      app.showNotice(DemoError.from(error).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun create(draft: APIKeyDraft) {
    try {
      val secret = app.dependencies.apiKeys.createAPIKey(draft)
      showingCreate = false
      createdSecret = secret
      load()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      app.showNotice(DemoError.from(error).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun update(key: APIKeyMetadata, draft: APIKeyDraft) {
    try {
      app.dependencies.apiKeys.updateAPIKey(key.id, draft)
      editingKey = null
      load()
      app.showNotice("Metadados da chave atualizados.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      app.showNotice(DemoError.from(error).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  AccountScaffold(
    title = "Chaves de integração",
    onBack = onBack,
    actions = {
      if (!isDemoViewerLocked) {
        AccountToolbarAction {
          IconButton(
            onClick = { showingCreate = true },
            modifier = Modifier.testTag("api-key.create"),
          ) {
            Icon(
              imageVector = Icons.Filled.Add,
              contentDescription = "Criar chave",
              tint = RentivoColors.emerald,
            )
          }
        }
      }
    },
  ) { padding ->
    PullToRefreshBox(
      isRefreshing = isRefreshing,
      onRefresh = {
        scope.launch {
          isRefreshing = true
          load()
          isRefreshing = false
        }
      },
      modifier = Modifier.fillMaxSize().padding(padding),
    ) {
      PageStateView(
        state = state,
        emptyTitle = "Nenhuma chave de integração",
        emptyMessage =
          "Crie uma chave de API para conectar integrações externas com escopos e acessos " +
            "controlados.",
        emptyIcon = Icons.Filled.VpnKey,
        emptyActionTitle = if (canCreate) "Criar chave" else null,
        emptyAction = if (canCreate) ({ showingCreate = true }) else null,
        retry = { scope.launch { load() } },
      ) { keys ->
        LazyColumn(
          modifier = Modifier.fillMaxSize(),
          contentPadding = PaddingValues(RentivoSpacing.page),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
        ) {
          items(items = keys, key = { it.id.rawValue }) { key ->
            APIKeyCard(
              key = key,
              showsActions = !isDemoViewerLocked,
              onEdit = { editingKey = key },
              onRevoke = { keyPendingRevoke = key },
            )
          }
        }
      }
    }
  }

  if (showingCreate) {
    APIKeyFormScreen(
      existing = null,
      onDismiss = { showingCreate = false },
      onSubmit = ::create,
    )
  }

  editingKey?.let { key ->
    APIKeyFormScreen(
      existing = key,
      onDismiss = { editingKey = null },
      onSubmit = { draft -> update(key, draft) },
    )
  }

  createdSecret?.let { secret ->
    APIKeySecretScreen(created = secret, onDismiss = { createdSecret = null })
  }

  keyPendingRevoke?.let { key ->
    AlertDialog(
      onDismissRequest = { keyPendingRevoke = null },
      title = { Text(text = "Revogar esta chave de integração?") },
      text = {
        Text(
          text = "Qualquer integração usando \"${key.name}\" perderá acesso imediatamente. " +
            "Esta ação não pode ser desfeita."
        )
      },
      confirmButton = {
        TextButton(
          onClick = {
            keyPendingRevoke = null
            scope.launch { revoke(key) }
          },
          modifier = Modifier.testTag("api-key.revoke.confirm"),
        ) {
          Text(text = "Revogar chave", color = RentivoColors.destructiveText)
        }
      },
      dismissButton = {
        TextButton(
          onClick = { keyPendingRevoke = null },
          modifier = Modifier.testTag("api-key.revoke.cancel"),
        ) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
      containerColor = RentivoColors.surface,
    )
  }
}

/** The one place on this tab that keeps the brutalist card: iOS draws a `RentivoCard` here too. */
@Composable
private fun APIKeyCard(
  key: APIKeyMetadata,
  showsActions: Boolean,
  onEdit: () -> Unit,
  onRevoke: () -> Unit,
) {
  RentivoCard {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny)) {
      Text(text = key.name, style = RentivoTypography.cardTitle, color = RentivoColors.ink)
      Row(
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(
          imageVector = Icons.Filled.VpnKey,
          contentDescription = null,
          tint = RentivoColors.secondaryInk,
          modifier = Modifier.size(16.dp),
        )
        Text(
          text = key.hint,
          style = RentivoTypography.caption.copy(fontFamily = FontFamily.Monospace),
          color = RentivoColors.secondaryInk,
        )
      }
    }
    Spacer(modifier = Modifier.size(RentivoSpacing.medium))
    // Scopes are never truncated: this is the only place outside the edit sheet that shows what an
    // integration is allowed to do, so the card grows instead.
    Text(
      text = key.scopes.map { it.label }.sorted().joinToString(separator = " · "),
      style = RentivoTypography.subheadline,
      color = RentivoColors.secondaryInk,
    )
    Spacer(modifier = Modifier.size(RentivoSpacing.medium))
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
      DateColumn(
        title = "Criada em",
        value = key.createdAt,
        alignment = Alignment.Start,
      )
      Spacer(modifier = Modifier.weight(1f))
      DateColumn(
        title = "Expira em",
        value = key.expiresAt,
        alignment = Alignment.End,
      )
    }
    Spacer(modifier = Modifier.size(RentivoSpacing.medium))
    Row(
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = Icons.Filled.People,
        contentDescription = null,
        tint = RentivoColors.secondaryInk,
        modifier = Modifier.size(16.dp),
      )
      Text(
        text = ptBRCount(
          key.grants.size + key.unavailableGrantCount,
          singular = "acesso",
          plural = "acessos",
        ),
        style = RentivoTypography.caption.copy(fontWeight = FontWeight.SemiBold),
        color = RentivoColors.secondaryInk,
      )
    }
    if (showsActions) {
      Spacer(modifier = Modifier.size(RentivoSpacing.medium))
      // `RentivoButton` already expands to the available width, so the row splits the footer 50/50.
      Row(horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        RentivoButton(
          text = "Editar",
          onClick = onEdit,
          modifier = Modifier.weight(1f).testTag("api-key.edit"),
          color = RentivoColors.blue,
        )
        RentivoButton(
          text = "Revogar",
          onClick = onRevoke,
          modifier = Modifier.weight(1f).testTag("api-key.revoke"),
          color = RentivoColors.coral,
        )
      }
    }
  }
}

@Composable
private fun DateColumn(title: String, value: Instant, alignment: Alignment.Horizontal) {
  Column(
    horizontalAlignment = alignment,
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
  ) {
    Text(text = title, style = RentivoTypography.caption, color = RentivoColors.secondaryInk)
    Text(
      text = value.formattedPTBR(),
      style = RentivoTypography.metadata,
      color = RentivoColors.ink,
    )
  }
}

/**
 * The create/edit form. Port of the iOS `APIKeyFormView` sheet; the async submit itself lives in
 * the list screen so a dismissal never cancels an in-flight request.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun APIKeyFormScreen(
  existing: APIKeyMetadata?,
  onDismiss: () -> Unit,
  onSubmit: suspend (APIKeyDraft) -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val originalGrants = remember(existing) {
    val grants = existing?.grants
      ?: listOf(
        APIKeyGrant(
          resourceType = WorkspaceResourceType.USER,
          resourceID = WorkspaceID.personal,
        )
      )
    grants.associateBy { it.resourceID }
  }
  val grantEditRule = APIKeyGrantEditRule(
    originalGrantIDs = originalGrants.keys,
    unavailableGrantCount = existing?.unavailableGrantCount ?: 0,
  )
  val scopeEditRule = APIKeyScopeEditRule(
    originalScopes = existing?.scopes.orEmpty(),
    unavailableScopeCount = existing?.unavailableScopeCount ?: 0,
  )
  var name by rememberSaveable(existing?.id?.rawValue) {
    mutableStateOf(existing?.name ?: "Nova integração")
  }
  val nameValidationMessage = APIKeyNameRule.validationMessage(name)
  val scopes: SnapshotStateList<APIKeyScope> = remember(existing) {
    mutableStateListOf<APIKeyScope>().apply {
      addAll(existing?.scopes ?: setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ))
    }
  }
  val grantIDs: SnapshotStateList<WorkspaceID> = remember(existing) {
    mutableStateListOf<WorkspaceID>().apply { addAll(originalGrants.keys) }
  }
  var expiresAt by remember(existing) {
    mutableStateOf(
      existing?.expiresAt ?: Instant.now().plusSeconds(DEFAULT_VALIDITY_SECONDS)
    )
  }
  var options by remember { mutableStateOf<APIKeyOptions?>(null) }
  var optionsLoadError by remember { mutableStateOf<String?>(null) }
  var showingDatePicker by remember { mutableStateOf(false) }
  var submitState by remember(existing) { mutableStateOf(FormSubmitState.idle) }

  // The sheet installs its own back handler, but this one is registered later and therefore wins;
  // either way back dismisses only the form, never the API-key screen underneath it.
  BackHandler { if (!submitState.isSubmitting) onDismiss() }

  LaunchedEffect(Unit) {
    try {
      val loaded = app.dependencies.apiKeys.apiKeyOptions()
      options = loaded
      if (existing == null) {
        expiresAt = Instant.now().plusSeconds(loaded.defaultExpirationDays.toLong() * 86_400L)
      }
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      optionsLoadError = DemoError.from(error).message
    }
  }

  fun submit() {
    if (submitState.isSubmitting) return
    if (nameValidationMessage != null) return
    val grants = grantIDs.sortedBy { it.rawValue }.map { resourceID ->
      originalGrants[resourceID]
        ?: APIKeyGrant(
          resourceType = if (resourceID == WorkspaceID.personal) {
            WorkspaceResourceType.USER
          } else {
            WorkspaceResourceType.ORGANIZATION
          },
          resourceID = resourceID,
        )
    }
    val draft = APIKeyDraft(
      name = name.trim(),
      scopes = scopes.toSet(),
      grants = grants,
      expiresAt = expiresAt,
      shouldUpdateGrants = existing == null || grantEditRule.shouldUpdate(grantIDs.toSet()),
      shouldUpdateScopes = existing == null || scopeEditRule.shouldUpdate(scopes.toSet()),
    )
    submitState = submitState.start()
    scope.launch {
      try {
        onSubmit(draft)
      } finally {
        submitState = submitState.finish()
      }
    }
  }

  FullScreenSheet(onDismissRequest = onDismiss, dismissEnabled = !submitState.isSubmitting) {
    RentivoLargeTopBarScaffold(
      title = if (existing == null) "Nova chave" else "Editar chave",
      navigationIcon = {
        TopBarChip {
          TextButton(onClick = onDismiss) {
            Text(text = "Cancelar", color = RentivoColors.emerald)
          }
        }
      },
      actions = {
        AccountToolbarAction {
          TextButton(
            onClick = { submit() },
            enabled = !submitState.isSubmitting && options != null && nameValidationMessage == null &&
              (scopes.isNotEmpty() || !scopeEditRule.canEdit) &&
              (grantIDs.isNotEmpty() || !grantEditRule.canEdit),
            modifier = Modifier.testTag("api-key.submit"),
          ) {
            Text(text = if (existing == null) "Criar" else "Salvar")
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
        AccountSection(
          title = "Identificação",
          rows = listOf({
            AccountFieldRow(
              placeholder = "Nome",
              value = name,
              onValueChange = { name = it },
              modifier = Modifier.testTag("api-key.name"),
            )
          }),
        )
        nameValidationMessage?.let { AccountFootnote(text = it) }

        AccountSection(
          title = "Escopos seguros",
          rows = buildList {
            if (!scopeEditRule.canEdit) {
              add({
                AccountFootnote(
                  text = "Há ${existing?.unavailableScopeCount} escopo(s) desconhecido(s). " +
                    "Os escopos serão preservados e não podem ser alterados nesta versão.",
                )
              })
            }
            options.orEmptyScopes().forEach { scope -> add({
              ToggleRow(
                label = scope.label,
                checked = scopes.contains(scope),
                enabled = scopeEditRule.canEdit,
                onCheckedChange = { enabled ->
                  if (enabled) {
                    if (!scopes.contains(scope)) scopes.add(scope)
                  } else {
                    scopes.remove(scope)
                  }
                },
              )
            }) }
          },
        )

        AccountSection(
          title = "Acesso",
          rows = buildList {
            if (!grantEditRule.canEdit) {
              add({
                AccountFootnote(
                  text = "Há ${existing?.unavailableGrantCount} acesso(s) oculto(s). " +
                    "Os acessos serão preservados e não podem ser alterados enquanto estiverem " +
                    "indisponíveis.",
                )
              })
            }
            add({
              ResourceToggle(
                label = "Conta pessoal",
                id = WorkspaceID.personal,
                grantIDs = grantIDs,
                enabled = grantEditRule.canEdit,
              )
            })
            options.orEmptyWorkspaces().filter { it.resourceID != WorkspaceID.personal }.forEach { workspace ->
              add({
                ResourceToggle(
                  label = workspace.name ?: "Conta pessoal",
                  id = workspace.resourceID,
                  grantIDs = grantIDs,
                  enabled = grantEditRule.canEdit,
                )
              })
            }
          },
        )

        AccountSection(
          title = "Validade",
          rows = listOf({
            if (existing == null) {
              ExpiryRow(value = expiresAt, onClick = { showingDatePicker = true })
            } else {
              // PATCH does not accept `expires_at`; presenting this as editable would silently
              // discard the user's selection. Existing keys therefore expose it as read-only.
              AccountLabeledRow(label = "Expira em", value = expiresAt.formattedPTBR())
            }
          }),
        )
        optionsLoadError?.let { message ->
          AccountFootnote(text = "Não foi possível carregar as opções da chave: $message")
        }
      }
    }
  }

  if (existing == null && showingDatePicker) {
    ExpiryDatePicker(
      initial = expiresAt,
      onDismiss = { showingDatePicker = false },
      onSelect = { expiresAt = it },
    )
  }
}

/** The iOS compact `DatePicker` row: a plain label with the date sitting in a recessed chip. */
@Composable
private fun ExpiryRow(value: Instant, onClick: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium)
      .testTag("api-key.expires-at"),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = "Expira em",
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Text(
      text = value.formattedPTBR(),
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier
        .clip(RoundedCornerShape(8.dp))
        .background(RentivoColors.paper)
        .padding(horizontal = RentivoSpacing.small, vertical = RentivoSpacing.tiny + 2.dp),
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpiryDatePicker(
  initial: Instant,
  onDismiss: () -> Unit,
  onSelect: (Instant) -> Unit,
) {
  val pickerState = rememberDatePickerState(initialSelectedDateMillis = initial.toEpochMilli())
  DatePickerDialog(
    onDismissRequest = onDismiss,
    confirmButton = {
      TextButton(
        onClick = {
          pickerState.selectedDateMillis?.let { onSelect(Instant.ofEpochMilli(it)) }
          onDismiss()
        }
      ) {
        Text(text = "OK")
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss) { Text(text = "Cancelar") }
    },
  ) {
    DatePicker(state = pickerState)
  }
}

@Composable
private fun ResourceToggle(
  label: String,
  id: WorkspaceID,
  grantIDs: SnapshotStateList<WorkspaceID>,
  enabled: Boolean = true,
) {
  ToggleRow(
    label = label,
    checked = grantIDs.contains(id),
    enabled = enabled,
    onCheckedChange = { enabled ->
      if (enabled) {
        if (!grantIDs.contains(id)) grantIDs.add(id)
      } else {
        grantIDs.remove(id)
      }
    },
  )
}

/** One iOS `Toggle` row: label on the left, a scaled-down switch on the right. */
@Composable
private fun ToggleRow(
  label: String,
  checked: Boolean,
  enabled: Boolean = true,
  onCheckedChange: (Boolean) -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.tiny),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = label,
      style = RentivoTypography.body,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Switch(
      checked = checked,
      onCheckedChange = onCheckedChange,
      enabled = enabled,
      colors = rentivoSwitchColors(),
      modifier = Modifier.scale(SWITCH_SCALE),
    )
  }
}

/** Port of the iOS `APIKeySecretView` sheet: the one and only time the secret is readable. */
@Composable
private fun APIKeySecretScreen(created: CreatedAPIKeySecret, onDismiss: () -> Unit) {
  // Without this the system back press reaches the enclosing tab's handler and pops the entire
  // API-key screen, destroying the one-time secret before the user has copied it. Back dismisses
  // only this overlay — the same thing "Já copiei" does, matching the iOS sheet-dismiss semantics.
  var acknowledged by remember { mutableStateOf(false) }
  val clipboard = LocalClipboardManager.current
  BackHandler { if (acknowledged) onDismiss() }

  FullScreenSheet(onDismissRequest = onDismiss, dismissEnabled = acknowledged) {
    AccountScaffold(title = "Segredo da chave", onBack = null) { padding ->
      Column(
        modifier = Modifier
          .fillMaxSize()
          .padding(padding)
          .padding(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
      ) {
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Icon(
            imageVector = Icons.Filled.GppMaybe,
            contentDescription = null,
            tint = RentivoColors.amber,
          )
          Text(text = "Copie agora", style = RentivoTypography.title, color = RentivoColors.amber)
        }
        Text(
          text = "Este segredo não será exibido novamente.",
          style = RentivoTypography.body,
          color = RentivoColors.ink,
        )
        // Selection only: the secret is never written to the clipboard on the user's behalf.
        SelectionContainer {
          Text(
            text = created.secret,
            style = TextStyle(
              fontFamily = FontFamily.Monospace,
              fontWeight = FontWeight.Bold,
              fontSize = RentivoTypography.body.fontSize,
            ),
            color = RentivoColors.ink,
            modifier = Modifier
              .fillMaxWidth()
              .background(RentivoColors.surface, RoundedCornerShape(12.dp))
              .padding(RentivoSpacing.large)
              .testTag("api-key.secret"),
          )
        }
        TextButton(
          onClick = { clipboard.setText(AnnotatedString(created.secret)) },
          modifier = Modifier.testTag("api-key.secret.copy"),
        ) { Text("Copiar segredo") }
        Spacer(modifier = Modifier.weight(1f))
        RentivoButton(
          text = if (acknowledged) "Concluir" else "Confirmo que guardei o segredo",
          onClick = {
            if (acknowledged) onDismiss() else acknowledged = true
          },
          modifier = Modifier.testTag("api-key.secret.dismiss"),
        )
      }
    }
  }
}

/** The PT-BR labels of the scopes an integration key can hold. */
private val APIKeyScope.label: String
  get() = when (this) {
    APIKeyScope.PROFILE_READ -> "Ler perfil"
    APIKeyScope.ACCOUNT_WRITE -> "Alterar conta"
    APIKeyScope.SECURITY_MANAGE -> "Gerenciar segurança"
    APIKeyScope.API_KEYS_MANAGE -> "Gerenciar chaves de API"
    APIKeyScope.ORGANIZATIONS_READ -> "Ler organizações"
    APIKeyScope.ORGANIZATIONS_WRITE -> "Alterar organizações"
    APIKeyScope.ORGANIZATIONS_MEMBERS -> "Gerenciar membros"
    APIKeyScope.BILLINGS_READ -> "Ler cobranças"
    APIKeyScope.BILLINGS_WRITE -> "Alterar cobranças"
    APIKeyScope.BILLS_READ -> "Ler faturas"
    APIKeyScope.BILLS_WRITE -> "Alterar faturas"
    APIKeyScope.EXPENSES_READ -> "Ler despesas"
    APIKeyScope.EXPENSES_WRITE -> "Alterar despesas"
    APIKeyScope.FILES_READ -> "Ler arquivos"
    APIKeyScope.FILES_WRITE -> "Alterar arquivos"
    APIKeyScope.COMMUNICATIONS_READ -> "Ler comunicações"
    APIKeyScope.COMMUNICATIONS_SEND -> "Enviar comunicações"
    APIKeyScope.THEMES_READ -> "Ler temas"
    APIKeyScope.THEMES_WRITE -> "Alterar temas"
    APIKeyScope.EXPORTS_CREATE -> "Criar exportações"
  }

private fun APIKeyOptions?.orEmptyScopes(): List<APIKeyScope> =
  this?.scopes?.sortedBy(APIKeyScope::wire).orEmpty()

private fun APIKeyOptions?.orEmptyWorkspaces() = this?.workspaces.orEmpty()
