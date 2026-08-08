package app.rentivo.features.organizations

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.House
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldColors
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.ptBRCount
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.Billing
import app.rentivo.domain.DemoError
import app.rentivo.domain.LoadState
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationMember
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.ThemeTarget
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/** One organization plus the number of billings owned by it, as the list renders them. */
private data class OrganizationListItem(
  val organization: Organization,
  val billingCount: Int,
)

/**
 * The organizations list. Port of `OrganizationListView` in
 * `ios/Rentivo/Features/Organizations/OrganizationViews.swift`.
 *
 * [refreshKey] is the Compose stand-in for the iOS `onMutation` closure the detail screen calls: the
 * tab bumps it after a detail-level mutation so this list reloads while staying composed underneath,
 * exactly like a `NavigationStack` root does.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrganizationListView(
  refreshKey: Int,
  onOpenOrganization: (OrganizationID) -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var state: LoadState<List<OrganizationListItem>> by remember { mutableStateOf(LoadState.Idle) }
  var pendingCount by remember { mutableIntStateOf(0) }
  var showingCreate by remember { mutableStateOf(false) }
  var showingInvitations by remember { mutableStateOf(false) }
  var isRefreshing by remember { mutableStateOf(false) }

  // `viewerMode` is a demo-mode-only concept: `LiveDemoRepository.setViewerMode` just flips a local
  // flag with zero effect on the live server, so gating a real affordance on it while connected live
  // would hide a working action for no server-backed reason. Organization creation has no per-payload
  // capability to check (it isn't scoped to an existing organization), so we only respect the demo
  // toggle when actually running against the mock store.
  val canCreateOrganization = app.usesLiveAPI || !app.demoSettings.viewerMode

  suspend fun load() {
    // Only show the loading spinner when nothing is on screen yet; pull-to-refresh and every tab
    // revisit (`LaunchedEffect(app.dataRevision)`) otherwise refresh in place instead of tearing
    // down the list.
    when (state) {
      LoadState.Idle, is LoadState.Failed -> state = LoadState.Loading
      else -> Unit
    }
    try {
      val organizations = app.dependencies.organizations.listOrganizations()
      val billings = app.dependencies.billings.listBillings()
      val values = organizations.map { organization ->
        OrganizationListItem(
          organization = organization,
          billingCount = billings.count {
            it.owner.workspaceID.rawValue == organization.id.rawValue
          },
        )
      }
      pendingCount = app.dependencies.invitations.listPendingInvitations().size
      state = if (values.isEmpty()) LoadState.Empty else LoadState.Loaded(values)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      when (state) {
        is LoadState.Loaded, LoadState.Empty ->
          app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)

        else -> state = LoadState.Failed(DemoError.from(throwable))
      }
    }
  }

  LaunchedEffect(app.dataRevision, refreshKey) { load() }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = { Text(text = "Organizações", style = RentivoTypography.title) },
        colors = rentivoTopAppBarColors(),
        actions = {
          if (canCreateOrganization) {
            TextButton(
              onClick = { showingCreate = true },
              modifier = Modifier.testTag("organization.create"),
            ) {
              Icon(imageVector = Icons.Filled.Add, contentDescription = null)
              Spacer(modifier = Modifier.width(RentivoSpacing.tiny))
              Text(text = "Criar", style = RentivoTypography.cardTitle)
            }
          }
        },
      )
    },
  ) { padding ->
    PullToRefreshBox(
      isRefreshing = isRefreshing,
      onRefresh = {
        scope.launch {
          isRefreshing = true
          try {
            load()
          } finally {
            isRefreshing = false
          }
        }
      },
      modifier = Modifier.fillMaxSize().padding(padding),
    ) {
      PageStateView(
        state = state,
        emptyTitle = "Nenhuma organização ainda",
        emptyMessage =
          "Organizações reúnem cobranças e membros sob papéis e permissões compartilhados. " +
            "Crie uma para colaborar com sua equipe.",
        emptyIcon = Icons.Filled.Apartment,
        emptyActionTitle = if (canCreateOrganization) "Criar organização" else null,
        emptyAction = if (canCreateOrganization) ({ showingCreate = true }) else null,
        retry = { scope.launch { load() } },
      ) { organizations ->
        LazyColumn(
          modifier = Modifier.fillMaxSize(),
          contentPadding = PaddingValues(RentivoSpacing.page),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
        ) {
          if (pendingCount > 0) {
            item(key = "pending-invitations") {
              PendingInvitationsCard(
                pendingCount = pendingCount,
                onClick = { showingInvitations = true },
              )
            }
          }
          items(items = organizations, key = { it.organization.id.rawValue }) { item ->
            OrganizationCard(
              item = item,
              onClick = { onOpenOrganization(item.organization.id) },
            )
          }
        }
      }
    }
  }

  if (showingCreate) {
    OpaqueOverlay {
      OrganizationFormView(
        existing = null,
        onSaved = { load() },
        onDismiss = { showingCreate = false },
      )
    }
  }

  if (showingInvitations) {
    OpaqueOverlay {
      InvitationListView(
        onMutation = { load() },
        onDismiss = { showingInvitations = false },
      )
    }
  }
}

@Composable
private fun PendingInvitationsCard(pendingCount: Int, onClick: () -> Unit) {
  RentivoCard(
    modifier = Modifier
      .clickable(onClick = onClick)
      .testTag("organization.invitations.open"),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      IconLabel(
        text = ptBRCount(pendingCount, singular = "convite pendente", plural = "convites pendentes"),
        icon = Icons.Filled.MarkEmailUnread,
        style = RentivoTypography.cardTitle,
      )
      Spacer(modifier = Modifier.weight(1f))
      Icon(
        imageVector = Icons.Filled.ChevronRight,
        contentDescription = null,
        tint = RentivoColors.ink,
      )
    }
  }
}

@Composable
private fun OrganizationCard(item: OrganizationListItem, onClick: () -> Unit) {
  RentivoCard(modifier = Modifier.clickable(onClick = onClick)) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      Row(verticalAlignment = Alignment.Top) {
        Icon(
          imageVector = Icons.Filled.Apartment,
          contentDescription = null,
          tint = RentivoColors.emerald,
          modifier = Modifier.size(28.dp),
        )
        Spacer(modifier = Modifier.width(RentivoSpacing.medium))
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        ) {
          Text(
            text = item.organization.name,
            style = RentivoTypography.cardTitle,
            color = RentivoColors.ink,
          )
          Text(
            text = item.organization.currentUserRole.label,
            style = RentivoTypography.metadata,
            color = RentivoColors.secondaryInk,
          )
        }
        Icon(
          imageVector = Icons.Filled.ChevronRight,
          contentDescription = null,
          tint = RentivoColors.secondaryInk,
        )
      }
      Row(verticalAlignment = Alignment.CenterVertically) {
        IconLabel(
          text = ptBRCount(item.organization.members.size, singular = "membro", plural = "membros"),
          icon = Icons.Filled.People,
          color = RentivoColors.secondaryInk,
          style = RentivoTypography.metadata,
        )
        Spacer(modifier = Modifier.weight(1f))
        IconLabel(
          text = ptBRCount(item.billingCount, singular = "cobrança", plural = "cobranças"),
          icon = Icons.Filled.House,
          color = RentivoColors.secondaryInk,
          style = RentivoTypography.metadata,
        )
      }
      IconLabel(
        text = if (item.organization.requiresMFA) "MFA obrigatório" else "MFA opcional",
        icon = if (item.organization.requiresMFA) Icons.Filled.Security else Icons.Filled.LockOpen,
        color = if (item.organization.requiresMFA) {
          RentivoColors.emerald
        } else {
          RentivoColors.secondaryInk
        },
        style = RentivoTypography.metadata,
      )
    }
  }
}

/**
 * Create/edit organization sheet. Port of `OrganizationFormView`.
 *
 * [onSaved] is the iOS `onSaved: () async -> Void`; it runs before the sheet closes so the presenting
 * screen is already refreshed by the time the notice appears.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrganizationFormView(
  existing: Organization?,
  onSaved: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var name by remember(existing?.id) { mutableStateOf(existing?.name ?: "") }
  var pixKey by remember(existing?.id) { mutableStateOf(existing?.pix?.key ?: "") }
  var merchantName by remember(existing?.id) { mutableStateOf(existing?.pix?.merchantName ?: "") }
  var city by remember(existing?.id) { mutableStateOf(existing?.pix?.merchantCity ?: "") }
  var pixValidationMessage: String? by remember(existing?.id) { mutableStateOf(null) }

  BackHandler { onDismiss() }

  suspend fun save() {
    val trimmedKey = pixKey.trim()
    val trimmedMerchantName = merchantName.trim()
    val trimmedCity = city.trim()
    // Mirrors BillingFormView's PIX validation: a blank key means no PIX at all, but once a key is
    // present the recipient name/city are required, and must respect the server's column limits
    // (`OrganizationUpdateRequest.pix_merchant_name` maxLength 25, `pix_merchant_city` maxLength 15)
    // so the follow-up PATCH in `createOrganization`/`updateOrganization` can't 422 on data the form
    // already accepted.
    pixValidationMessage = when {
      trimmedKey.isEmpty() -> null
      trimmedMerchantName.isEmpty() || trimmedCity.isEmpty() ->
        "Informe o nome e a cidade do recebedor para usar uma chave PIX."

      trimmedMerchantName.length > 25 -> "O nome do recebedor deve ter até 25 caracteres."
      trimmedCity.length > 15 -> "A cidade do recebedor deve ter até 15 caracteres."
      else -> null
    }
    if (pixValidationMessage != null) return
    val pix = if (trimmedKey.isEmpty()) {
      null
    } else {
      PixConfiguration(
        key = trimmedKey,
        merchantName = trimmedMerchantName,
        merchantCity = trimmedCity,
      )
    }
    val draft = OrganizationDraft(name = name, pix = pix)
    try {
      if (existing != null) {
        app.dependencies.organizations.updateOrganization(id = existing.id, draft = draft)
      } else {
        app.dependencies.organizations.createOrganization(draft)
      }
      onSaved()
      app.showNotice(if (existing == null) "Organização criada." else "Organização atualizada.")
      onDismiss()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      SheetTopBar(
        title = if (existing == null) "Nova organização" else "Editar organização",
        confirmTitle = "Salvar",
        confirmEnabled = name.isNotEmpty(),
        confirmTestTag = "organization.form.save",
        onCancel = onDismiss,
        onConfirm = { scope.launch { save() } },
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
      FormSection(title = "Organização") {
        OutlinedTextField(
          value = name,
          onValueChange = { name = it },
          label = { Text(text = "Nome") },
          singleLine = true,
          colors = rentivoFieldColors(),
          modifier = Modifier.fillMaxWidth().testTag("organization.form.name"),
        )
      }
      FormSection(title = "PIX") {
        OutlinedTextField(
          value = pixKey,
          onValueChange = { pixKey = it },
          label = { Text(text = "Chave") },
          singleLine = true,
          colors = rentivoFieldColors(),
          modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
          value = merchantName,
          onValueChange = { merchantName = it },
          label = { Text(text = "Nome do recebedor") },
          singleLine = true,
          colors = rentivoFieldColors(),
          modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
          value = city,
          onValueChange = { city = it },
          label = { Text(text = "Cidade") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
          colors = rentivoFieldColors(),
          modifier = Modifier.fillMaxWidth(),
        )
      }
      pixValidationMessage?.let { message ->
        FormSection(title = "Revise os campos") {
          IconLabel(
            text = message,
            icon = Icons.Filled.Error,
            color = RentivoColors.coral,
            modifier = Modifier.testTag("organization.form.validation"),
          )
        }
      }
    }
  }
}

/**
 * Organization detail. Port of `OrganizationDetailView`.
 *
 * [onMutation] mirrors the iOS closure of the same name — every mutation calls `refreshAll()`, which
 * reloads this screen and then lets the presenting list reload too.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrganizationDetailView(
  organizationId: OrganizationID,
  onMutation: suspend () -> Unit,
  onOpenTheme: (ThemeTarget) -> Unit,
  onBack: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var state: LoadState<Organization> by remember { mutableStateOf(LoadState.Idle) }
  var billings: List<Billing> by remember { mutableStateOf(emptyList()) }
  var showingEdit by remember { mutableStateOf(false) }
  var showingInvite by remember { mutableStateOf(false) }
  var confirmingMFA by remember { mutableStateOf(false) }
  var confirmingDelete by remember { mutableStateOf(false) }

  suspend fun load() {
    // Same "don't blank on refresh" rule as the organization list: every member/role/MFA/billing
    // mutation calls `refreshAll()` -> `load()`, and `LaunchedEffect(app.dataRevision)` reruns on
    // demo-state changes too, so resetting to Loading unconditionally would flash a spinner over an
    // already-visible organization on every one of those actions.
    when (state) {
      LoadState.Idle, is LoadState.Failed -> state = LoadState.Loading
      else -> Unit
    }
    try {
      val loadedOrganization = app.dependencies.organizations.organization(id = organizationId)
      val loadedBillings = app.dependencies.billings.listBillings()
      billings = loadedBillings
      state = LoadState.Loaded(loadedOrganization)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      when (state) {
        is LoadState.Loaded, LoadState.Empty ->
          app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)

        else -> state = LoadState.Failed(DemoError.from(throwable))
      }
    }
  }

  suspend fun refreshAll() {
    load()
    onMutation()
  }

  suspend fun changeRole(member: OrganizationMember, role: OrganizationRole) {
    try {
      app.dependencies.organizations.updateMemberRole(
        organizationID = organizationId,
        userID = member.userID,
        role = role,
      )
      refreshAll()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun remove(member: OrganizationMember) {
    try {
      app.dependencies.organizations.removeMember(
        organizationID = organizationId,
        userID = member.userID,
      )
      refreshAll()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun toggleMFA() {
    val organization = state.value ?: return
    try {
      app.dependencies.organizations.setOrganizationMFA(
        organizationID = organizationId,
        required = !organization.requiresMFA,
      )
      refreshAll()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun transfer(billing: Billing, organization: Organization) {
    try {
      app.dependencies.organizations.transferBilling(
        billingID = billing.id,
        toOrganizationID = organization.id,
      )
      refreshAll()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun deleteOrganization() {
    try {
      app.dependencies.organizations.deleteOrganization(id = organizationId)
      onMutation()
      onBack()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = { Text(text = "Organização", style = RentivoTypography.cardTitle) },
        colors = rentivoTopAppBarColors(),
        navigationIcon = {
          IconButton(onClick = onBack) {
            Icon(
              imageVector = Icons.AutoMirrored.Filled.ArrowBack,
              contentDescription = "Voltar",
            )
          }
        },
        actions = {
          if (state.value?.capabilities?.canManage == true) {
            TextButton(
              onClick = { showingEdit = true },
              modifier = Modifier.testTag("organization.edit"),
            ) {
              Text(text = "Editar", style = RentivoTypography.cardTitle)
            }
          }
        },
      )
    },
  ) { padding ->
    PageStateView(
      state = state,
      modifier = Modifier.padding(padding),
      retry = { scope.launch { load() } },
    ) { organization ->
      Column(
        modifier = Modifier
          .fillMaxSize()
          .padding(padding)
          .verticalScroll(rememberScrollState())
          .padding(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
      ) {
        RentivoCard {
          Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
            Text(
              text = organization.name,
              style = RentivoTypography.title,
              color = RentivoColors.ink,
            )
            IconLabel(
              text = organization.currentUserRole.label,
              icon = Icons.Filled.VerifiedUser,
            )
            IconLabel(
              text = if (organization.pix?.isComplete == true) {
                "PIX configurado"
              } else {
                "PIX pendente"
              },
              icon = Icons.Filled.QrCode2,
            )
          }
        }

        MemberSection(
          organization = organization,
          onInvite = { showingInvite = true },
          onChangeRole = { member, role -> scope.launch { changeRole(member, role) } },
          onRemove = { member -> scope.launch { remove(member) } },
        )

        PolicySection(
          organization = organization,
          onToggleRequested = { confirmingMFA = true },
        )

        BillingSection(
          organization = organization,
          billings = billings,
          onTransfer = { billing -> scope.launch { transfer(billing, organization) } },
        )

        RentivoButton(
          onClick = { onOpenTheme(ThemeTarget.Organization(organizationId)) },
          color = RentivoColors.blue,
          modifier = Modifier.testTag("organization.theme"),
        ) {
          Icon(
            imageVector = Icons.Filled.Palette,
            contentDescription = null,
            tint = Color.White,
          )
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
          Text(
            text = "Aparência da organização",
            style = RentivoTypography.cardTitle,
            color = Color.White,
          )
        }

        if (organization.capabilities.canManage) {
          OutlinedButton(
            onClick = { confirmingDelete = true },
            modifier = Modifier.fillMaxWidth().testTag("organization.delete"),
          ) {
            Icon(
              imageVector = Icons.Filled.Delete,
              contentDescription = null,
              tint = RentivoColors.coral,
            )
            Spacer(modifier = Modifier.width(RentivoSpacing.small))
            Text(
              text = "Excluir organização",
              style = RentivoTypography.cardTitle,
              color = RentivoColors.coral,
            )
          }
        } else {
          IconLabel(
            text = "Seu papel permite consultar esta organização, sem alterar sua configuração.",
            icon = Icons.Filled.Visibility,
            color = RentivoColors.secondaryInk,
            style = RentivoTypography.metadata,
          )
        }
      }
    }
  }

  val organization = state.value
  if (confirmingMFA && organization != null) {
    AlertDialog(
      onDismissRequest = { confirmingMFA = false },
      containerColor = RentivoColors.surface,
      title = {
        Text(text = if (organization.requiresMFA) "Tornar MFA opcional?" else "Exigir MFA?")
      },
      text = { Text(text = "A política será aplicada a todos os membros desta organização.") },
      confirmButton = {
        TextButton(
          onClick = {
            confirmingMFA = false
            scope.launch { toggleMFA() }
          },
        ) {
          Text(text = "Confirmar")
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingMFA = false }) { Text(text = "Cancelar") }
      },
    )
  }

  if (confirmingDelete) {
    AlertDialog(
      onDismissRequest = { confirmingDelete = false },
      containerColor = RentivoColors.surface,
      title = { Text(text = "Excluir organização?") },
      text = { Text(text = "Primeiro transfira todas as cobranças vinculadas.") },
      confirmButton = {
        TextButton(
          onClick = {
            confirmingDelete = false
            scope.launch { deleteOrganization() }
          },
        ) {
          Text(text = "Excluir", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingDelete = false }) { Text(text = "Cancelar") }
      },
    )
  }

  if (showingEdit && organization != null) {
    OpaqueOverlay {
      OrganizationFormView(
        existing = organization,
        onSaved = { refreshAll() },
        onDismiss = { showingEdit = false },
      )
    }
  }

  if (showingInvite && organization != null) {
    OpaqueOverlay {
      InviteMemberView(
        organization = organization,
        onSent = { refreshAll() },
        onDismiss = { showingInvite = false },
      )
    }
  }
}

@Composable
private fun MemberSection(
  organization: Organization,
  onInvite: () -> Unit,
  onChangeRole: (OrganizationMember, OrganizationRole) -> Unit,
  onRemove: (OrganizationMember) -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      SectionTitle(title = "Membros", icon = Icons.Filled.People)
      Spacer(modifier = Modifier.weight(1f))
      if (organization.capabilities.canInvite) {
        IconButton(
          onClick = onInvite,
          modifier = Modifier.testTag("organization.invite"),
        ) {
          Icon(
            imageVector = Icons.Filled.PersonAdd,
            contentDescription = "Convidar membro",
            tint = RentivoColors.ink,
          )
        }
      }
    }
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        organization.members.forEach { member ->
          MemberRow(
            member = member,
            canManage = organization.capabilities.canManage,
            onChangeRole = { role -> onChangeRole(member, role) },
            onRemove = { onRemove(member) },
          )
        }
      }
    }
  }
}

@Composable
private fun MemberRow(
  member: OrganizationMember,
  canManage: Boolean,
  onChangeRole: (OrganizationRole) -> Unit,
  onRemove: () -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }

  Row(verticalAlignment = Alignment.CenterVertically) {
    Column(modifier = Modifier.weight(1f)) {
      Text(
        text = member.email,
        style = RentivoTypography.subheadlineEmphasized,
        color = RentivoColors.ink,
      )
      Text(
        text = member.role.label,
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
    if (member.role == OrganizationRole.ADMIN) {
      Icon(
        imageVector = Icons.Filled.WorkspacePremium,
        contentDescription = null,
        tint = RentivoColors.amber,
      )
    } else if (canManage) {
      Box {
        IconButton(onClick = { expanded = true }) {
          Icon(
            imageVector = Icons.Filled.MoreHoriz,
            contentDescription = "Opções de ${member.email}",
            tint = RentivoColors.ink,
          )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
          // Admin has no menu at all (see the `member.role == ADMIN` branch above), so offering
          // "admin" here would promote a member to a role with no way back through the UI. The
          // member's current role is also excluded: re-selecting it is a no-op that only clutters
          // the menu.
          OrganizationRole.entries
            .filter { it != OrganizationRole.ADMIN && it != member.role }
            .forEach { role ->
              DropdownMenuItem(
                text = { Text(text = role.label) },
                onClick = {
                  expanded = false
                  onChangeRole(role)
                },
              )
            }
          HorizontalDivider()
          DropdownMenuItem(
            text = { Text(text = "Remover", color = RentivoColors.coral) },
            onClick = {
              expanded = false
              onRemove()
            },
          )
        }
      }
    }
  }
}

@Composable
private fun PolicySection(organization: Organization, onToggleRequested: () -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Política de segurança", icon = Icons.Filled.Security)
    RentivoCard {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = "Autenticação em duas etapas",
            style = RentivoTypography.cardTitle,
            color = RentivoColors.ink,
          )
          Text(
            text = if (organization.requiresMFA) "Obrigatória para membros" else "Opcional",
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
        }
        // A real Switch (not a decoration behind a click listener) so TalkBack can focus and
        // activate it directly. The change handler never applies the tap's intended value: it only
        // opens the confirmation dialog. The switch's visual position stays driven entirely by
        // `organization.requiresMFA`, so it only moves once `toggleMFA()` actually persists the
        // change and reloads — if the user cancels the dialog, nothing changes and the toggle
        // silently reverts to its true state.
        Switch(
          checked = organization.requiresMFA,
          onCheckedChange = { onToggleRequested() },
          enabled = organization.capabilities.canManage,
          colors = SwitchDefaults.colors(
            checkedThumbColor = RentivoColors.surface,
            checkedTrackColor = RentivoColors.emerald,
            uncheckedThumbColor = RentivoColors.secondaryInk,
            uncheckedTrackColor = RentivoColors.paper,
          ),
          modifier = Modifier
            .semantics { contentDescription = "Autenticação em duas etapas obrigatória" }
            .testTag("organization.mfa.toggle"),
        )
      }
    }
  }
}

@Composable
private fun BillingSection(
  organization: Organization,
  billings: List<Billing>,
  onTransfer: (Billing) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }
  val owned = billings.filter { it.owner.workspaceID.rawValue == organization.id.rawValue }
  val personal = billings.filter { !it.owner.isOrganization }

  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Cobranças", icon = Icons.Filled.House)
    if (owned.isEmpty()) {
      Text(
        text = "Nenhuma cobrança pertence a esta organização.",
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
    } else {
      owned.forEach { billing ->
        RentivoCard {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
              text = billing.name,
              style = RentivoTypography.subheadlineEmphasized,
              color = RentivoColors.ink,
            )
            Spacer(modifier = Modifier.weight(1f))
          }
        }
      }
    }
    if (personal.isNotEmpty() && organization.capabilities.canCreateBilling) {
      Box {
        OutlinedButton(
          onClick = { expanded = true },
          modifier = Modifier.testTag("organization.billing.transfer"),
        ) {
          Icon(
            imageVector = Icons.Filled.SwapHoriz,
            contentDescription = null,
            tint = RentivoColors.ink,
          )
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
          Text(
            text = "Transferir cobrança para cá",
            style = RentivoTypography.cardTitle,
            color = RentivoColors.ink,
          )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
          personal.forEach { billing ->
            DropdownMenuItem(
              text = { Text(text = billing.name) },
              onClick = {
                expanded = false
                onTransfer(billing)
              },
            )
          }
        }
      }
    }
  }
}

/**
 * A full-bleed, opaque layer above the tab content — the Compose stand-in for both a SwiftUI
 * `.sheet` and a `NavigationStack` push.
 *
 * The empty click listener is load-bearing: a `Box` that only paints a background does not consume
 * pointer events, so taps would otherwise reach the list rendered underneath.
 */
@Composable
internal fun OpaqueOverlay(content: @Composable () -> Unit) {
  Box(
    modifier = Modifier
      .rentivoPage()
      .clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        onClick = {},
      ),
  ) {
    content()
  }
}

/** The `Cancelar` / title / confirm toolbar every sheet in this feature shares. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SheetTopBar(
  title: String,
  confirmTitle: String,
  confirmEnabled: Boolean,
  confirmTestTag: String,
  onCancel: () -> Unit,
  onConfirm: () -> Unit,
) {
  TopAppBar(
    title = { Text(text = title, style = RentivoTypography.cardTitle) },
    colors = rentivoTopAppBarColors(),
    navigationIcon = {
      TextButton(onClick = onCancel) {
        Text(text = "Cancelar", style = RentivoTypography.cardTitle)
      }
    },
    actions = {
      TextButton(
        onClick = onConfirm,
        enabled = confirmEnabled,
        modifier = Modifier.testTag(confirmTestTag),
      ) {
        Text(text = confirmTitle, style = RentivoTypography.cardTitle)
      }
    },
  )
}

/** A titled group of fields, the Compose analog of a SwiftUI `Form` `Section`. */
@Composable
internal fun FormSection(title: String, content: @Composable () -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Text(text = title, style = RentivoTypography.metadata, color = RentivoColors.secondaryInk)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) { content() }
    }
  }
}

/** The Compose analog of SwiftUI's `Label(text, systemImage:)`. */
@Composable
internal fun IconLabel(
  text: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.ink,
  style: TextStyle = RentivoTypography.subheadline,
) {
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = color,
      modifier = Modifier.size(20.dp),
    )
    Text(text = text, style = style, color = color)
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun rentivoTopAppBarColors() = TopAppBarDefaults.topAppBarColors(
  containerColor = RentivoColors.paper,
  titleContentColor = RentivoColors.ink,
  navigationIconContentColor = RentivoColors.ink,
  actionIconContentColor = RentivoColors.emerald,
)

@Composable
internal fun rentivoFieldColors(): TextFieldColors = OutlinedTextFieldDefaults.colors(
  focusedTextColor = RentivoColors.ink,
  unfocusedTextColor = RentivoColors.ink,
  focusedContainerColor = RentivoColors.surface,
  unfocusedContainerColor = RentivoColors.surface,
  cursorColor = RentivoColors.emerald,
  focusedBorderColor = RentivoColors.ink,
  unfocusedBorderColor = RentivoColors.secondaryInk,
  focusedLabelColor = RentivoColors.emerald,
  unfocusedLabelColor = RentivoColors.secondaryInk,
)
