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
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.MutationGate
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
import app.rentivo.domain.APIKeyMetadata
import app.rentivo.domain.APIKeyOptions
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.APIKeyValidation
import app.rentivo.domain.CreatedAPIKeySecret
import app.rentivo.domain.DemoError
import app.rentivo.domain.LoadState
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant

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

  suspend fun update(key: APIKeyMetadata, draft: APIKeyDraft, updateGrants: Boolean) {
    try {
      app.dependencies.apiKeys.updateAPIKey(key.id, draft, updateGrants = updateGrants)
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
              showsActions = !isDemoViewerLocked && key.revokedAt == null,
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
      onSubmit = { draft, _ -> create(draft) },
    )
  }

  editingKey?.let { key ->
    APIKeyFormScreen(
      existing = key,
      onDismiss = { editingKey = null },
      onSubmit = { draft, updateGrants -> update(key, draft, updateGrants) },
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
      Row(
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(text = key.name, style = RentivoTypography.cardTitle, color = RentivoColors.ink)
        if (key.revokedAt != null) {
          Text(
            text = "Revogada",
            style = RentivoTypography.caption.copy(fontWeight = FontWeight.SemiBold),
            color = RentivoColors.coral,
            modifier = Modifier.testTag("api-key.revoked"),
          )
        }
      }
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
        text = ptBRCount(key.grants.size, singular = "acesso", plural = "acessos"),
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
  onSubmit: suspend (APIKeyDraft, Boolean) -> Unit,
) {
  val app = LocalAppModel.current
  val formScope = rememberCoroutineScope()
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
  val originalGrantIDs = remember(existing) {
    originalGrants.values.filter { it.available }.map { it.resourceID }.toSet()
  }
  var name by remember(existing) { mutableStateOf(existing?.name ?: "Nova integração") }
  val scopes: SnapshotStateList<APIKeyScope> = remember(existing) {
    mutableStateListOf<APIKeyScope>().apply {
      addAll(existing?.scopes ?: setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ))
    }
  }
  val grantIDs: SnapshotStateList<WorkspaceID> = remember(existing) {
    mutableStateListOf<WorkspaceID>().apply { addAll(originalGrantIDs) }
  }
  var expiresAt by remember(existing) {
    mutableStateOf(existing?.expiresAt ?: Instant.now())
  }
  var options by remember { mutableStateOf<APIKeyOptions?>(null) }
  var optionsError by remember { mutableStateOf<DemoError?>(null) }
  var showingDatePicker by remember { mutableStateOf(false) }
  val mutationGate = remember(existing) { MutationGate() }

  // The sheet installs its own back handler, but this one is registered later and therefore wins;
  // either way back dismisses only the form, never the API-key screen underneath it.
  BackHandler { if (!mutationGate.isRunning) onDismiss() }

  suspend fun loadOptions() {
    optionsError = null
    try {
      val loaded = app.dependencies.apiKeys.apiKeyOptions()
      options = loaded
      if (existing == null) {
        scopes.retainAll(loaded.scopes.toSet())
        expiresAt = loaded.defaultExpiration()
      }
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      optionsError = DemoError.from(error)
    }
  }

  LaunchedEffect(Unit) { loadOptions() }

  suspend fun submit() {
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
    val loadedOptions = options ?: return
    onSubmit(
      APIKeyDraft(
        name = name.trim(),
        scopes = scopes.toSet(),
        grants = grants,
        expiresAt = existing?.expiresAt ?: loadedOptions.clampedExpiration(expiresAt),
      ),
      grantIDs.toSet() != originalGrantIDs,
    )
  }

  FullScreenSheet(onDismissRequest = onDismiss, dismissEnabled = !mutationGate.isRunning) {
    RentivoLargeTopBarScaffold(
      title = if (existing == null) "Nova chave" else "Editar chave",
      navigationIcon = {
        TopBarChip {
          TextButton(onClick = onDismiss, enabled = !mutationGate.isRunning) {
            Text(text = "Cancelar", color = RentivoColors.emerald)
          }
        }
      },
      actions = {
        AccountToolbarAction {
          TextButton(
            onClick = { formScope.launch { mutationGate.run { submit() } } },
            enabled = !mutationGate.isRunning && options != null &&
              options?.scopes?.isNotEmpty() == true &&
              APIKeyValidation.isValidName(name) && scopes.isNotEmpty() && grantIDs.isNotEmpty(),
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

        AccountSection(
          title = "Escopos seguros",
          rows = options?.scopes?.map { apiKeyScope ->
            {
              ToggleRow(
                label = apiKeyScope.label,
                checked = scopes.contains(apiKeyScope),
                onCheckedChange = { enabled ->
                  if (enabled) {
                    if (!scopes.contains(apiKeyScope)) scopes.add(apiKeyScope)
                  } else {
                    scopes.remove(apiKeyScope)
                  }
                },
              )
            }
          } ?: listOf({
            OptionsStatusRow(
              error = optionsError,
              onRetry = { formScope.launch { loadOptions() } },
            )
          }),
        )

        AccountSection(
          title = "Acesso",
          rows = options?.let { apiKeyOptions ->
            buildList {
              add({
                ResourceToggle(
                  label = apiKeyOptions.personalWorkspace.name,
                  id = apiKeyOptions.personalWorkspace.resourceID,
                  grantIDs = grantIDs,
                )
              })
              apiKeyOptions.organizations.forEach { workspace ->
                add({
                  ResourceToggle(
                    label = workspace.name,
                    id = workspace.resourceID,
                    grantIDs = grantIDs,
                  )
                })
              }
            }
          } ?: listOf({
            OptionsStatusRow(
              error = optionsError,
              onRetry = { formScope.launch { loadOptions() } },
            )
          }),
        )

        if (existing == null && options != null) {
          AccountSection(
            title = "Validade",
            rows = listOf({
              ExpiryRow(
                value = expiresAt,
                onClick = { showingDatePicker = true },
              )
            }),
          )
        }
      }
    }
  }

  val expiryOptions = options
  if (showingDatePicker && expiryOptions != null) {
    ExpiryDatePicker(
      initial = expiresAt,
      minimum = Instant.now().plusSeconds(60),
      maximum = expiryOptions.maximumExpiration(),
      onDismiss = { showingDatePicker = false },
      onSelect = { expiresAt = expiryOptions.clampedExpiration(it) },
    )
  }
}

@Composable
private fun OptionsStatusRow(error: DemoError?, onRetry: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = AccountRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = error?.message ?: "Carregando opções…",
      style = RentivoTypography.body,
      color = if (error == null) RentivoColors.secondaryInk else RentivoColors.destructiveText,
      modifier = Modifier.weight(1f),
    )
    if (error != null) {
      TextButton(onClick = onRetry) { Text("Tentar novamente") }
    }
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
  minimum: Instant,
  maximum: Instant,
  onDismiss: () -> Unit,
  onSelect: (Instant) -> Unit,
) {
  val pickerState = rememberDatePickerState(
    initialSelectedDateMillis = initial.toEpochMilli(),
    selectableDates = object : androidx.compose.material3.SelectableDates {
      override fun isSelectableDate(utcTimeMillis: Long): Boolean =
        utcTimeMillis >= minimum.toEpochMilli() && utcTimeMillis <= maximum.toEpochMilli()
    },
  )
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
) {
  ToggleRow(
    label = label,
    checked = grantIDs.contains(id),
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
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
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
  BackHandler { onDismiss() }

  FullScreenSheet(onDismissRequest = onDismiss) {
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
        Spacer(modifier = Modifier.weight(1f))
        RentivoButton(
          text = "Já copiei",
          onClick = onDismiss,
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
