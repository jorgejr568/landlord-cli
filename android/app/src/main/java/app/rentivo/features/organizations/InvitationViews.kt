package app.rentivo.features.organizations

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Drafts
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.AppTab
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.IconLabel
import app.rentivo.designsystem.MutationGate
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoLargeTopBarScaffold
import app.rentivo.designsystem.RentivoListDivider
import app.rentivo.designsystem.RentivoListGroup
import app.rentivo.designsystem.RentivoProminentButton
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTonalButton
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.TopBarChip
import app.rentivo.domain.DemoError
import app.rentivo.domain.Invitation
import app.rentivo.domain.LoadState
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationInviteEmail
import app.rentivo.domain.OrganizationRole
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/** The chevron pair on a picker row, sized to sit beside the 17sp value rather than tower over it. */
private val PickerGlyphSize = 18.dp

/**
 * Pending invitations sheet. Port of `InvitationListView` in
 * `ios/Rentivo/Features/Organizations/InvitationViews.swift`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvitationListView(
  onMutation: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var state: LoadState<List<Invitation>> by remember { mutableStateOf(LoadState.Idle) }
  val mutationGate = remember { MutationGate() }

  suspend fun load() {
    // Only blank the sheet with a spinner on first load; a `dataRevision` bump while the sheet is
    // open (e.g. toggling a demo setting) refreshes in place instead of tearing down the
    // currently-shown list.
    when (state) {
      LoadState.Idle, is LoadState.Failed -> state = LoadState.Loading
      else -> Unit
    }
    try {
      val invitations = app.dependencies.invitations.listPendingInvitations()
      state = if (invitations.isEmpty()) LoadState.Empty else LoadState.Loaded(invitations)
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

  suspend fun respond(invitation: Invitation, accept: Boolean) {
    try {
      var requiresMFASetup = false
      if (accept) {
        requiresMFASetup = app.dependencies.invitations
          .acceptInvitation(id = invitation.id).mfaSetupRequired
      } else {
        app.dependencies.invitations.declineInvitation(id = invitation.id)
      }
      load()
      onMutation()
      if (requiresMFASetup) {
        onDismiss()
        app.selectedTab = AppTab.ACCOUNT
        app.showNotice(
          "Sua nova organização exige MFA. Abra Segurança para configurar TOTP ou uma passkey.",
          AppNotice.Kind.WARNING,
        )
        return
      }
      app.showNotice(if (accept) "Convite aceito." else "Convite recusado.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  RentivoLargeTopBarScaffold(
    title = "Convites",
    navigationIcon = {
      TopBarChip {
        IconButton(onClick = onDismiss) {
          Icon(
            imageVector = Icons.Filled.Close,
            contentDescription = "Fechar",
            tint = RentivoColors.ink,
          )
        }
      }
    },
  ) { padding ->
    PageStateView(
      state = state,
      modifier = Modifier.padding(padding),
      emptyTitle = "Nenhum convite pendente",
      emptyMessage =
        "Convites para participar de organizações aparecerão aqui assim que alguém te convidar.",
      emptyIcon = Icons.Filled.Drafts,
      retry = { scope.launch { load() } },
    ) { invitations ->
      LazyColumn(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
      ) {
        items(items = invitations, key = { it.id.rawValue }) { invitation ->
          InvitationRow(
            invitation = invitation,
            showsViewerNotice = !app.usesLiveAPI && app.demoSettings.viewerMode,
            onRespond = { accept ->
              scope.launch { mutationGate.run { respond(invitation, accept) } }
            },
          )
        }
      }
    }
  }
}

@Composable
private fun InvitationRow(
  invitation: Invitation,
  showsViewerNotice: Boolean,
  onRespond: (Boolean) -> Unit,
) {
  // Flat: these rows are the sheet's own content, and iOS renders them as plain `List` rows. A
  // second ink outline inside a presented sheet only competes with the sheet's edge.
  RentivoCard(flat = true) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      Text(
        text = invitation.organizationName,
        style = RentivoTypography.cardTitle,
        color = RentivoColors.ink,
      )
      IconLabel(
        text = invitation.role.label,
        icon = Icons.Filled.AdminPanelSettings,
        style = RentivoTypography.caption,
        tint = RentivoColors.ink,
      )
      if (showsViewerNotice) {
        IconLabel(
          text = "Ações indisponíveis no modo visualizador.",
          icon = Icons.Filled.Visibility,
          style = RentivoTypography.caption,
        )
      } else {
        // Content-hugging, as on iOS: two capsules sitting at the leading edge rather than a pair
        // of half-width slabs. "Recusar" is tinted, not destructive — declining an invitation
        // deletes nothing.
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          RentivoProminentButton(
            text = "Aceitar",
            onClick = { onRespond(true) },
            modifier = Modifier.testTag("invitation.accept"),
          )
          RentivoTonalButton(
            text = "Recusar",
            onClick = { onRespond(false) },
            modifier = Modifier.testTag("invitation.decline"),
          )
        }
      }
    }
  }
}

/** Invite-a-member sheet. Port of `InviteMemberView`. */
@Composable
fun InviteMemberView(
  organization: Organization,
  onSent: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var email by remember { mutableStateOf("") }
  var role by remember { mutableStateOf(OrganizationRole.VIEWER) }
  var roleMenuExpanded by remember { mutableStateOf(false) }
  val mutationGate = remember { MutationGate() }

  suspend fun invite() {
    if (!OrganizationInviteEmail.isValid(email)) {
      app.showNotice(
        OrganizationInviteEmail.validationMessage(email) ?: "Informe um e-mail válido.",
        AppNotice.Kind.WARNING,
      )
      return
    }
    try {
      app.dependencies.organizations.inviteMember(
        organizationID = organization.id,
        email = OrganizationInviteEmail.normalized(email),
        role = role,
      )
      onSent()
      app.showNotice("Convite enviado.")
      onDismiss()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  BackHandler { if (!mutationGate.isRunning) onDismiss() }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      SheetTopBar(
        confirmTitle = "Convidar",
        confirmEnabled = !mutationGate.isRunning && OrganizationInviteEmail.isValid(email),
        confirmTestTag = "invitation.send",
        cancelEnabled = !mutationGate.isRunning,
        onCancel = onDismiss,
        onConfirm = { scope.launch { mutationGate.run { invite() } } },
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
      // The iOS screen keeps its navigation title in the automatic (large) display mode, so the
      // title belongs in the content, above the form, not in the toolbar between the two actions.
      Text(text = "Convidar membro", style = RentivoTypography.display, color = RentivoColors.ink)
      RentivoListGroup {
        FormFieldRow(
          placeholder = "E-mail",
          value = email,
          onValueChange = { email = it },
          modifier = Modifier.testTag("invitation.email"),
          keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            keyboardType = KeyboardType.Email,
          ),
        )
        RentivoListDivider()
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = ListRowMinHeight)
            .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.small),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(text = "Função", style = RentivoTypography.body, color = RentivoColors.ink)
          Spacer(modifier = Modifier.weight(1f))
          Box {
            TextButton(
              onClick = { roleMenuExpanded = true },
              modifier = Modifier.testTag("invitation.role"),
            ) {
              Text(text = role.label, style = RentivoTypography.body, color = RentivoColors.emerald)
              Spacer(modifier = Modifier.width(RentivoSpacing.tiny))
              Icon(
                imageVector = Icons.Filled.UnfoldMore,
                contentDescription = null,
                tint = RentivoColors.emerald,
                modifier = Modifier.size(PickerGlyphSize),
              )
            }
            DropdownMenu(
              expanded = roleMenuExpanded,
              onDismissRequest = { roleMenuExpanded = false },
            ) {
              OrganizationRole.entries.forEach { option ->
                DropdownMenuItem(
                  text = { Text(text = option.label) },
                  onClick = {
                    role = option
                    roleMenuExpanded = false
                  },
                )
              }
            }
          }
        }
        // This disclosure only describes the mock store's in-memory behavior; against the live API
        // the invite is actually persisted server-side, so showing it there would be misleading
        // demo residue. It belongs to the form, so it rides on the same plate as the fields — the
        // last row of the iOS `Form`, below its own separator.
        if (!app.usesLiveAPI) {
          RentivoListDivider()
          IconLabel(
            text = "O convite ficará pendente apenas na memória do app.",
            icon = Icons.Outlined.Info,
            style = RentivoTypography.caption,
            tint = RentivoColors.emerald,
            textColor = RentivoColors.secondaryInk,
            modifier = Modifier
              .fillMaxWidth()
              .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
          )
        }
      }
    }
  }
}
