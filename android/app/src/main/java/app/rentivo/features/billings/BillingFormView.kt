package app.rentivo.features.billings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoListDivider
import app.rentivo.designsystem.RentivoListField
import app.rentivo.designsystem.RentivoListGroup
import app.rentivo.designsystem.RentivoSegmentedPicker
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.TopBarChip
import app.rentivo.designsystem.centavosFromInput
import app.rentivo.designsystem.displayText
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemID
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.DemoError
import app.rentivo.domain.Money
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.PixFormFields
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ValidationIssue
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/** A recurring item while it is being edited, before it becomes a [BillingItem]. */
private data class EditableBillingItem(
  val id: BillingItemID,
  val description: String = "",
  val centavos: Int = 0,
  val type: BillingItemType = BillingItemType.FIXED,
) {
  fun domain(sortOrder: Int): BillingItem = BillingItem(
    id = id,
    description = description,
    amount = Money(centavos = centavos),
    type = type,
    sortOrder = sortOrder,
  )

  companion object {
    fun from(item: BillingItem): EditableBillingItem = EditableBillingItem(
      id = item.id,
      description = item.description,
      centavos = item.type.normalizedTemplateAmount(item.amount.centavos),
      type = item.type,
    )

    fun blank(): EditableBillingItem =
      EditableBillingItem(id = BillingItemID(rawValue = UUID.randomUUID().toString()))
  }
}

/** A recipient while it is being edited, before it becomes a [BillingRecipient]. */
private data class EditableRecipient(
  val id: RecipientID,
  val name: String = "",
  val email: String = "",
) {
  val isBlank: Boolean get() = name.trim().isEmpty() && email.trim().isEmpty()

  fun domain(): BillingRecipient = BillingRecipient(
    id = id,
    name = name.trim(),
    email = email.trim(),
  )

  companion object {
    fun from(recipient: BillingRecipient): EditableRecipient = EditableRecipient(
      id = recipient.id,
      name = recipient.name,
      email = recipient.email,
    )

    fun blank(): EditableRecipient =
      EditableRecipient(id = RecipientID(rawValue = UUID.randomUUID().toString()))
  }
}

/**
 * Create/edit form for a billing. Port of `ios/Rentivo/Features/Billings/BillingFormView.swift`.
 *
 * The iOS view is a `Form` presented as a sheet inside its own `NavigationStack`. Callers put it in
 * a `FullScreenSheet`, which supplies the sheet; this composable supplies the inline Cancelar/Salvar
 * navigation bar and the inset-grouped sections.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BillingFormView(
  existing: Billing? = null,
  onSaved: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()

  var name by rememberSaveable(existing?.id?.rawValue) { mutableStateOf(existing?.name.orEmpty()) }
  var billingDescription by rememberSaveable(existing?.id?.rawValue) {
    mutableStateOf(existing?.description.orEmpty())
  }
  var ownerIDRaw by rememberSaveable(existing?.id?.rawValue) {
    mutableStateOf(existing?.owner?.workspaceID?.rawValue ?: WorkspaceID.personal.rawValue)
  }
  val ownerID = WorkspaceID(ownerIDRaw)
  val items: SnapshotStateList<EditableBillingItem> = remember {
    existing?.items.orEmpty().map(EditableBillingItem::from).toMutableStateList()
  }
  var pixKey by rememberSaveable(existing?.id?.rawValue) { mutableStateOf(existing?.pixOverride?.key.orEmpty()) }
  var pixMerchantName by rememberSaveable(existing?.id?.rawValue) {
    mutableStateOf(existing?.pixOverride?.merchantName.orEmpty())
  }
  var pixMerchantCity by rememberSaveable(existing?.id?.rawValue) {
    mutableStateOf(existing?.pixOverride?.merchantCity.orEmpty())
  }
  val recipients: SnapshotStateList<EditableRecipient> = remember {
    existing?.recipients.orEmpty().map(EditableRecipient::from).toMutableStateList()
  }
  val replyTo: SnapshotStateList<EditableRecipient> = remember {
    existing?.replyTo.orEmpty().map(EditableRecipient::from).toMutableStateList()
  }
  val validationIssues = remember { mutableStateListOf<ValidationIssue>() }
  var pixRecipientRequiredMessage by remember { mutableStateOf<String?>(null) }
  var saving by remember { mutableStateOf(false) }
  var organizations by remember { mutableStateOf(emptyList<BillingOwner.Organization>()) }
  var organizationsLoaded by remember { mutableStateOf(false) }
  var organizationsLoadError by remember { mutableStateOf<String?>(null) }

  val ownerChoices = ownerChoices(
    currentUserID = app.currentUser.id,
    currentOwner = existing?.owner,
    organizations = organizations,
  )

  fun submit() {
    // Claim the submission synchronously in the click handler. Setting this inside the launched
    // coroutine leaves a window where two queued taps can both cross the boundary.
    if (saving) return
    val owner = ownerChoices.firstOrNull { it.workspaceID == ownerID }
    if (owner == null) {
      app.showNotice("Não foi possível confirmar o responsável.", AppNotice.Kind.WARNING)
      return
    }
    // A wholly empty row is the user leaving the "Adicionar destinatário" placeholder untouched, so
    // it is dropped rather than reported as invalid. Partially filled rows still fail validation
    // below, because the update replaces the billing's whole recipient set.
    val draftRecipients = recipients.filterNot { it.isBlank }.map { it.domain() }
    val draftReplyTo = replyTo.filterNot { it.isBlank }.map { it.domain() }
    val pixFields = PixFormFields(
      key = pixKey,
      merchantName = pixMerchantName,
      merchantCity = pixMerchantCity,
    )
    pixRecipientRequiredMessage = pixFields.validationMessage
    val draft = BillingDraft(
      name = name,
      description = billingDescription,
      owner = owner,
      items = items.mapIndexed { index, item -> item.domain(sortOrder = index) },
      pixOverride = pixFields.configuration,
      recipients = draftRecipients,
      replyTo = draftReplyTo,
    )
    validationIssues.clear()
    validationIssues.addAll(draft.validate())
    if (validationIssues.isNotEmpty() || pixRecipientRequiredMessage != null) return

    saving = true
    scope.launch {
      try {
        if (existing == null) {
          app.dependencies.billings.createBilling(draft = draft)
        } else {
          app.dependencies.billings.updateBilling(id = existing.id, draft = draft)
        }
        onSaved()
        app.showNotice(if (existing == null) "Cobrança criada." else "Cobrança atualizada.")
        onDismiss()
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
      } finally {
        saving = false
      }
    }
  }

  suspend fun loadOrganizationOwners() {
    organizationsLoaded = false
    organizationsLoadError = null
    organizations = try {
      app.dependencies.apiKeys.apiKeyOptions().workspaces
        .filter { it.resourceType == WorkspaceResourceType.ORGANIZATION }
        .mapNotNull { option ->
          option.name?.let { name ->
            BillingOwner.Organization(OrganizationID(option.resourceID.rawValue), name)
          }
        }
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (failure: Throwable) {
      organizationsLoadError = DemoError.from(failure).message
      emptyList()
    }
    organizationsLoaded = organizationsLoadError == null
  }

  LaunchedEffect(Unit) { loadOrganizationOwners() }

  // Mirrors `.interactiveDismissDisabled(saving)`: a save in flight must not be backed out from.
  // The handler stays enabled while saving so it swallows the gesture instead of letting the
  // enclosing sheet dismiss the form out from under the request.
  BackHandler { if (!saving) onDismiss() }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    // The enclosing sheet already sits below the status bar, so the bar must not inset itself a
    // second time; the navigation bar is still underneath the sheet and does need clearing.
    contentWindowInsets = WindowInsets.navigationBars,
    topBar = {
      CenterAlignedTopAppBar(
        windowInsets = WindowInsets(left = 0, top = 0, right = 0, bottom = 0),
        title = {
          Text(
            text = if (existing == null) "Nova cobrança" else "Editar cobrança",
            style = RentivoTypography.cardTitle,
            color = RentivoColors.ink,
          )
        },
        navigationIcon = {
          Box(modifier = Modifier.padding(start = RentivoSpacing.small)) {
            TopBarChip {
              TextButton(onClick = onDismiss) {
                Text(
                  text = "Cancelar",
                  style = RentivoTypography.body,
                  color = RentivoColors.emerald,
                )
              }
            }
          }
        },
        actions = {
          val saveEnabled = !saving && organizationsLoaded
          Box(modifier = Modifier.padding(end = RentivoSpacing.small)) {
            TopBarChip {
              TextButton(
                onClick = ::submit,
                enabled = saveEnabled,
                modifier = Modifier.testTag("billing.form.save"),
              ) {
                Text(
                  text = "Salvar",
                  style = RentivoTypography.body.copy(fontWeight = FontWeight.SemiBold),
                  color = if (saveEnabled) RentivoColors.emerald else RentivoColors.secondaryInk,
                )
              }
            }
          }
        },
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
          containerColor = RentivoColors.paper,
          titleContentColor = RentivoColors.ink,
          navigationIconContentColor = RentivoColors.emerald,
          actionIconContentColor = RentivoColors.emerald,
        ),
      )
    },
  ) { padding ->
    LazyColumn(
      modifier = Modifier.padding(padding).fillMaxSize().imePadding(),
      contentPadding = PaddingValues(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      item {
        IdentificationSection(
          name = name,
          onNameChange = { name = it },
          description = billingDescription,
          onDescriptionChange = { billingDescription = it },
          ownerID = ownerID,
          onOwnerIDChange = { ownerIDRaw = it.rawValue },
          ownerChoices = ownerChoices,
          ownerEditable = existing?.owner !is BillingOwner.Organization,
        )
      }
      organizationsLoadError?.let { message ->
        item(key = "owner-load-error") {
          FormSection(title = "Responsável") {
            Text(message, style = RentivoTypography.caption, color = RentivoColors.coral)
            TextButton(onClick = { scope.launch { loadOrganizationOwners() } }) {
              Text("Tentar novamente")
            }
          }
        }
      }
      item { ItemsSection(items = items) }
      item {
        PixSection(
          key = pixKey,
          onKeyChange = { pixKey = it },
          merchantName = pixMerchantName,
          onMerchantNameChange = { pixMerchantName = it },
          merchantCity = pixMerchantCity,
          onMerchantCityChange = { pixMerchantCity = it },
        )
      }
      item {
        CommunicationSection(
          recipients = recipients,
          replyTo = replyTo,
        )
      }
      if (validationIssues.isNotEmpty() || pixRecipientRequiredMessage != null) {
        item {
          ValidationSection(
            issues = validationIssues,
            pixRecipientRequiredMessage = pixRecipientRequiredMessage,
          )
        }
      }
    }
  }
}

/**
 * "Pessoal", the billing's current owner when it is something else, and every organization the user
 * belongs to — deduplicated by workspace id, in that order.
 */
private fun ownerChoices(
  currentUserID: Int,
  currentOwner: BillingOwner?,
  organizations: List<BillingOwner.Organization>,
): List<BillingOwner> {
  val owners = mutableListOf<BillingOwner>(
    BillingOwner.User(id = currentUserID, name = "Pessoal")
  )
  if (currentOwner != null && owners.none { it.workspaceID == currentOwner.workspaceID }) {
    owners.add(currentOwner)
  }
  val existingIDs = owners.map { it.workspaceID }.toSet()
  owners.addAll(
    organizations.filterNot { existingIDs.contains(it.workspaceID) }
  )
  return owners
}

@Composable
private fun IdentificationSection(
  name: String,
  onNameChange: (String) -> Unit,
  description: String,
  onDescriptionChange: (String) -> Unit,
  ownerID: WorkspaceID,
  onOwnerIDChange: (WorkspaceID) -> Unit,
  ownerChoices: List<BillingOwner>,
  ownerEditable: Boolean,
) {
  FormSection(title = "Identificação") {
    FormTextField(
      label = "Nome",
      value = name,
      onValueChange = onNameChange,
      modifier = Modifier.testTag("billing.form.name"),
    )
    RentivoListDivider()
    FormTextField(
      label = "Descrição",
      value = description,
      onValueChange = onDescriptionChange,
      singleLine = false,
    )
    RentivoListDivider()
    OwnerPickerRow(
      ownerID = ownerID,
      onOwnerIDChange = onOwnerIDChange,
      ownerChoices = ownerChoices,
      ownerEditable = ownerEditable,
    )
  }
}

/** The iOS `Picker` row: label leading, current value and a disclosure glyph trailing. */
@Composable
private fun OwnerPickerRow(
  ownerID: WorkspaceID,
  onOwnerIDChange: (WorkspaceID) -> Unit,
  ownerChoices: List<BillingOwner>,
  ownerEditable: Boolean,
) {
  var expanded by remember { mutableStateOf(false) }
  val selectedName = ownerChoices.firstOrNull { it.workspaceID == ownerID }?.name.orEmpty()

  Box {
    FormRow(modifier = if (ownerEditable) Modifier.clickable { expanded = true } else Modifier) {
      Text(
        text = "Responsável",
        style = RentivoTypography.body,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      Text(
        text = selectedName,
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
      if (ownerEditable) {
        Icon(
          imageVector = Icons.Filled.UnfoldMore,
          contentDescription = null,
          tint = RentivoColors.secondaryInk,
          modifier = Modifier.size(18.dp),
        )
      }
    }
    DropdownMenu(expanded = ownerEditable && expanded, onDismissRequest = { expanded = false }) {
      ownerChoices.forEach { owner ->
        DropdownMenuItem(
          text = { Text(text = owner.name) },
          onClick = {
            onOwnerIDChange(owner.workspaceID)
            expanded = false
          },
        )
      }
    }
  }
}

@Composable
private fun ItemsSection(items: SnapshotStateList<EditableBillingItem>) {
  var editing by rememberSaveable { mutableStateOf(false) }

  FormSection(
    title = "Itens recorrentes",
    footer = "Use valor zero para itens variáveis que serão preenchidos em cada fatura.",
    headerAction = { EditToggle(editing = editing, onToggle = { editing = !editing }) },
  ) {
    items.forEachIndexed { index, item ->
      if (index > 0) RentivoListDivider(indent = 0.dp)
      FormTextField(
        label = "Descrição do item",
        value = item.description,
        onValueChange = { items[index] = items[index].copy(description = it) },
      )
      RentivoListDivider()
      FormRow {
        RentivoSegmentedPicker(
          options = BillingItemType.entries.map { it.label },
          selectedIndex = BillingItemType.entries.indexOf(item.type),
          onSelect = { typeIndex ->
            val type = BillingItemType.entries[typeIndex]
            items[index] = item.copy(
              centavos = type.normalizedTemplateAmount(item.centavos),
              type = type,
            )
          },
        )
      }
      if (item.type.showsTemplateAmount) {
        RentivoListDivider()
        FormCurrencyRow(
          label = "Valor do item",
          centavos = item.centavos,
          onCentavosChange = { items[index] = items[index].copy(centavos = it) },
        )
      }
      if (editing) {
        RentivoListDivider()
        FormRow {
          RowActions(
            canMoveUp = index > 0,
            canMoveDown = index < items.lastIndex,
            onMoveUp = { items.add(index - 1, items.removeAt(index)) },
            onMoveDown = { items.add(index + 1, items.removeAt(index)) },
            onDelete = { items.removeAt(index) },
          )
        }
      }
    }
    if (items.isNotEmpty()) RentivoListDivider(indent = 0.dp)
    AddRow(text = "Adicionar item", onClick = { items.add(EditableBillingItem.blank()) })
  }
}

@Composable
private fun PixSection(
  key: String,
  onKeyChange: (String) -> Unit,
  merchantName: String,
  onMerchantNameChange: (String) -> Unit,
  merchantCity: String,
  onMerchantCityChange: (String) -> Unit,
) {
  FormSection(
    title = "PIX opcional",
    footer = "Deixe em branco para herdar o PIX do responsável.",
  ) {
    FormTextField(
      label = "Chave PIX própria",
      value = key,
      onValueChange = onKeyChange,
      capitalization = KeyboardCapitalization.None,
      modifier = Modifier.testTag("billing.form.pix.key"),
    )
    RentivoListDivider()
    FormTextField(
      label = "Nome do recebedor",
      value = merchantName,
      onValueChange = onMerchantNameChange,
      modifier = Modifier.testTag("billing.form.pix.merchantName"),
    )
    RentivoListDivider()
    FormTextField(
      label = "Cidade do recebedor",
      value = merchantCity,
      onValueChange = onMerchantCityChange,
      capitalization = KeyboardCapitalization.Characters,
      modifier = Modifier.testTag("billing.form.pix.merchantCity"),
    )
  }
}

@Composable
private fun CommunicationSection(
  recipients: SnapshotStateList<EditableRecipient>,
  replyTo: SnapshotStateList<EditableRecipient>,
) {
  var editing by rememberSaveable { mutableStateOf(false) }

  FormSection(
    title = "Comunicação",
    footer = "Todos os destinatários listados recebem as comunicações desta cobrança.",
    headerAction = { EditToggle(editing = editing, onToggle = { editing = !editing }) },
  ) {
    recipients.forEachIndexed { index, recipient ->
      if (index > 0) RentivoListDivider(indent = 0.dp)
      FormTextField(
        label = "Nome do destinatário",
        value = recipient.name,
        onValueChange = { recipients[index] = recipients[index].copy(name = it) },
      )
      RentivoListDivider()
      FormTextField(
        label = "E-mail do destinatário",
        value = recipient.email,
        onValueChange = { recipients[index] = recipients[index].copy(email = it) },
        keyboardType = KeyboardType.Email,
        capitalization = KeyboardCapitalization.None,
      )
      if (editing) {
        RentivoListDivider()
        FormRow {
          RowActions(
            canMoveUp = index > 0,
            canMoveDown = index < recipients.lastIndex,
            onMoveUp = { recipients.add(index - 1, recipients.removeAt(index)) },
            onMoveDown = { recipients.add(index + 1, recipients.removeAt(index)) },
            onDelete = { recipients.removeAt(index) },
          )
        }
      }
    }
    if (recipients.isNotEmpty()) RentivoListDivider(indent = 0.dp)
    AddRow(
      text = "Adicionar destinatário",
      onClick = { recipients.add(EditableRecipient.blank()) },
      modifier = Modifier.testTag("billing.form.recipients.add"),
    )
    if (replyTo.isNotEmpty()) RentivoListDivider(indent = 0.dp)
    replyTo.forEachIndexed { index, contact ->
      if (index > 0) RentivoListDivider(indent = 0.dp)
      FormTextField(
        label = "Nome para resposta",
        value = contact.name,
        onValueChange = { replyTo[index] = contact.copy(name = it) },
      )
      RentivoListDivider()
      FormTextField(
        label = "E-mail para resposta",
        value = contact.email,
        onValueChange = { replyTo[index] = contact.copy(email = it) },
        keyboardType = KeyboardType.Email,
        capitalization = KeyboardCapitalization.None,
      )
      if (editing) {
        RentivoListDivider()
        FormRow {
          RowActions(
            canMoveUp = index > 0,
            canMoveDown = index < replyTo.lastIndex,
            onMoveUp = { replyTo.add(index - 1, replyTo.removeAt(index)) },
            onMoveDown = { replyTo.add(index + 1, replyTo.removeAt(index)) },
            onDelete = { replyTo.removeAt(index) },
          )
        }
      }
    }
    AddRow(
      text = "Adicionar resposta para",
      onClick = { replyTo.add(EditableRecipient.blank()) },
    )
  }
}

@Composable
private fun ValidationSection(
  issues: List<ValidationIssue>,
  pixRecipientRequiredMessage: String?,
) {
  FormSection(title = "Revise os campos") {
    issues.forEachIndexed { index, issue ->
      if (index > 0) RentivoListDivider()
      ValidationRow(message = issue.message)
    }
    pixRecipientRequiredMessage?.let { message ->
      if (issues.isNotEmpty()) RentivoListDivider()
      ValidationRow(message = message)
    }
  }
}

@Composable
private fun ValidationRow(message: String) {
  FormRow(modifier = Modifier.testTag("billing.form.validation")) {
    Icon(
      imageVector = Icons.Filled.Error,
      contentDescription = null,
      tint = RentivoColors.coral,
      modifier = Modifier.size(20.dp),
    )
    Text(
      text = message,
      style = RentivoTypography.subheadline,
      color = RentivoColors.coral,
    )
  }
}

/**
 * The iOS grouped-`Form` section: a subheadline header carrying an optional trailing action, a
 * white borderless plate holding the rows, and optional explanatory footer copy.
 *
 * The plate is a [RentivoListGroup] rather than a [app.rentivo.designsystem.RentivoCard]: nesting
 * outlined fields inside an outlined card double-draws every boundary and roughly doubles the
 * form's height. Rows place their own [RentivoListDivider]s, because a section mixes fields,
 * pickers and buttons that each need a different inset.
 */
@Composable
private fun FormSection(
  title: String,
  footer: String? = null,
  headerAction: @Composable (() -> Unit)? = null,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = RentivoSpacing.medium),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = title,
        style = RentivoTypography.subheadline,
        color = RentivoColors.secondaryInk,
        modifier = Modifier.weight(1f),
      )
      headerAction?.invoke()
    }
    RentivoListGroup(content = content)
    if (footer != null) {
      Text(
        text = footer,
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
        modifier = Modifier.padding(horizontal = RentivoSpacing.medium),
      )
    }
  }
}

/** One row of a section plate: full width, inset to the separator, at least a 44dp touch target. */
@Composable
private fun FormRow(
  modifier: Modifier = Modifier,
  content: @Composable RowScope.() -> Unit,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = 44.dp)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
    content = content,
  )
}

/**
 * A field row. Like an iOS `TextField` inside a `Form`, the label is the placeholder rather than a
 * floating caption, so an empty row is one line tall instead of two.
 */
@Composable
private fun FormTextField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  singleLine: Boolean = true,
  keyboardType: KeyboardType = KeyboardType.Text,
  capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
) {
  FormRow {
    RentivoListField(
      value = value,
      onValueChange = onValueChange,
      placeholder = label,
      singleLine = singleLine,
      keyboardOptions = KeyboardOptions(
        keyboardType = keyboardType,
        capitalization = capitalization,
        autoCorrectEnabled = capitalization != KeyboardCapitalization.None,
      ),
      modifier = modifier
        .weight(1f)
        .semantics { contentDescription = label },
    )
  }
}

/**
 * The centavos field as a grouped-form row: the label stays visible on the leading edge and the
 * masked amount is typed into a trailing monospaced field.
 */
@Composable
private fun FormCurrencyRow(
  label: String,
  centavos: Int,
  onCentavosChange: (Int) -> Unit,
) {
  FormRow {
    Text(text = label, style = RentivoTypography.body, color = RentivoColors.ink)
    RentivoListField(
      value = displayText(centavos),
      onValueChange = { onCentavosChange(centavosFromInput(it)) },
      monospace = true,
      textAlign = TextAlign.End,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      modifier = Modifier
        .weight(1f)
        .semantics { contentDescription = label },
    )
  }
}

/** The iOS `EditButton`: it reveals the rows' reorder and delete affordances rather than acting. */
@Composable
private fun EditToggle(editing: Boolean, onToggle: () -> Unit) {
  Text(
    text = if (editing) "Concluído" else "Editar",
    style = RentivoTypography.subheadlineEmphasized,
    color = RentivoColors.emerald,
    modifier = Modifier
      .clip(CircleShape)
      .clickable(onClick = onToggle)
      .padding(horizontal = RentivoSpacing.small, vertical = RentivoSpacing.tiny),
  )
}

/** The trailing "Adicionar …" row of a section: flush with the rows above it, body weight. */
@Composable
private fun AddRow(
  text: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  FormRow(modifier = modifier.clickable(onClick = onClick)) {
    Icon(
      imageVector = Icons.Filled.AddCircle,
      contentDescription = null,
      tint = RentivoColors.emerald,
      modifier = Modifier.size(20.dp),
    )
    Text(text = text, style = RentivoTypography.body, color = RentivoColors.emerald)
  }
}

/**
 * Reorder and delete controls for one editable row, revealed by the section's [EditToggle]. The iOS
 * form leans on `EditButton` plus `onDelete`/`onMove`, which have no Compose equivalent, so each row
 * carries its own controls behind the same toggle.
 */
@Composable
private fun RowActions(
  canMoveUp: Boolean,
  canMoveDown: Boolean,
  onMoveUp: () -> Unit,
  onMoveDown: () -> Unit,
  onDelete: () -> Unit,
) {
  IconButton(onClick = onMoveUp, enabled = canMoveUp) {
    Icon(
      imageVector = Icons.Filled.ArrowUpward,
      contentDescription = "Mover para cima",
      tint = RentivoColors.secondaryInk,
    )
  }
  IconButton(onClick = onMoveDown, enabled = canMoveDown) {
    Icon(
      imageVector = Icons.Filled.ArrowDownward,
      contentDescription = "Mover para baixo",
      tint = RentivoColors.secondaryInk,
    )
  }
  IconButton(onClick = onDelete) {
    Icon(
      imageVector = Icons.Filled.Delete,
      contentDescription = "Remover",
      tint = RentivoColors.coral,
    )
  }
}
