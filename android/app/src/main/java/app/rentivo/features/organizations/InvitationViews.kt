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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Drafts
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.domain.DemoError
import app.rentivo.domain.Invitation
import app.rentivo.domain.LoadState
import app.rentivo.domain.Organization
import app.rentivo.domain.OrganizationRole
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

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

  BackHandler { onDismiss() }

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
      if (accept) {
        app.dependencies.invitations.acceptInvitation(id = invitation.id)
      } else {
        app.dependencies.invitations.declineInvitation(id = invitation.id)
      }
      load()
      onMutation()
      app.showNotice(if (accept) "Convite aceito." else "Convite recusado.")
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
        title = { Text(text = "Convites", style = RentivoTypography.cardTitle) },
        colors = rentivoTopAppBarColors(),
        navigationIcon = {
          IconButton(onClick = onDismiss) {
            Icon(imageVector = Icons.Filled.Close, contentDescription = "Fechar")
          }
        },
      )
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
            onRespond = { accept -> scope.launch { respond(invitation, accept) } },
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
  RentivoCard {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      Text(
        text = invitation.organizationName,
        style = RentivoTypography.cardTitle,
        color = RentivoColors.ink,
      )
      IconLabel(
        text = invitation.role.label,
        icon = Icons.Filled.VerifiedUser,
        style = RentivoTypography.caption,
      )
      if (showsViewerNotice) {
        IconLabel(
          text = "Ações indisponíveis no modo visualizador.",
          icon = Icons.Filled.Visibility,
          color = RentivoColors.secondaryInk,
          style = RentivoTypography.caption,
        )
      } else {
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          RentivoButton(
            text = "Aceitar",
            onClick = { onRespond(true) },
            modifier = Modifier.weight(1f).testTag("invitation.accept"),
          )
          OutlinedButton(
            onClick = { onRespond(false) },
            modifier = Modifier.weight(1f).testTag("invitation.decline"),
          ) {
            Text(
              text = "Recusar",
              style = RentivoTypography.cardTitle,
              color = RentivoColors.coral,
            )
          }
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

  BackHandler { onDismiss() }

  suspend fun invite() {
    try {
      app.dependencies.organizations.inviteMember(
        organizationID = organization.id,
        email = email,
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

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      SheetTopBar(
        title = "Convidar membro",
        confirmTitle = "Convidar",
        // Deliberately weaker than `EmailAddress.isValid`: the iOS form gates only on an "@" being
        // present and lets the server reject anything else, so the ported button matches it exactly.
        confirmEnabled = email.contains("@"),
        confirmTestTag = "invitation.send",
        onCancel = onDismiss,
        onConfirm = { scope.launch { invite() } },
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
      RentivoCard {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text(text = "E-mail") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
              capitalization = KeyboardCapitalization.None,
              keyboardType = KeyboardType.Email,
            ),
            colors = rentivoFieldColors(),
            modifier = Modifier.fillMaxWidth().testTag("invitation.email"),
          )
          Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = "Função", style = RentivoTypography.body, color = RentivoColors.ink)
            Spacer(modifier = Modifier.weight(1f))
            Box {
              TextButton(
                onClick = { roleMenuExpanded = true },
                modifier = Modifier.testTag("invitation.role"),
              ) {
                Text(text = role.label, style = RentivoTypography.cardTitle)
                Spacer(modifier = Modifier.width(RentivoSpacing.tiny))
                Icon(imageVector = Icons.Filled.UnfoldMore, contentDescription = null)
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
        }
      }
      // This disclosure only describes the mock store's in-memory behavior; against the live API the
      // invite is actually persisted server-side, so showing it there would be misleading demo
      // residue.
      if (!app.usesLiveAPI) {
        IconLabel(
          text = "O convite ficará pendente apenas na memória do app.",
          icon = Icons.Filled.Info,
          color = RentivoColors.secondaryInk,
          style = RentivoTypography.caption,
        )
      }
    }
  }
}
