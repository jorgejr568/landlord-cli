package app.rentivo.features.billings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.CurrencyCentavosField
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemID
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.BillingRecipient
import app.rentivo.domain.DemoError
import app.rentivo.domain.Money
import app.rentivo.domain.Organization
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ValidationIssue
import app.rentivo.domain.WorkspaceID
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
      centavos = item.amount.centavos,
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
 * The iOS view is presented as a sheet inside its own `NavigationStack`; here it renders as a
 * full-screen surface with the same Cancelar/Salvar toolbar.
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

  var name by remember { mutableStateOf(existing?.name.orEmpty()) }
  var billingDescription by remember { mutableStateOf(existing?.description.orEmpty()) }
  var ownerID by remember {
    mutableStateOf(existing?.owner?.workspaceID ?: WorkspaceID.personal)
  }
  val items: SnapshotStateList<EditableBillingItem> = remember {
    existing?.items.orEmpty().map(EditableBillingItem::from).toMutableStateList()
  }
  var pixKey by remember { mutableStateOf(existing?.pixOverride?.key.orEmpty()) }
  var pixMerchantName by remember { mutableStateOf(existing?.pixOverride?.merchantName.orEmpty()) }
  var pixMerchantCity by remember { mutableStateOf(existing?.pixOverride?.merchantCity.orEmpty()) }
  val recipients: SnapshotStateList<EditableRecipient> = remember {
    existing?.recipients.orEmpty().map(EditableRecipient::from).toMutableStateList()
  }
  var replyTo by remember { mutableStateOf(existing?.replyTo.orEmpty()) }
  val validationIssues = remember { mutableStateListOf<ValidationIssue>() }
  var pixRecipientRequiredMessage by remember { mutableStateOf<String?>(null) }
  var saving by remember { mutableStateOf(false) }
  var organizations by remember { mutableStateOf(emptyList<Organization>()) }
  var organizationsLoaded by remember { mutableStateOf(false) }

  val ownerChoices = ownerChoices(
    currentUserID = app.currentUser.id,
    currentOwner = existing?.owner,
    organizations = organizations,
  )

  suspend fun save() {
    val owner = ownerChoices.firstOrNull { it.workspaceID == ownerID }
    if (owner == null) {
      app.showNotice("Não foi possível confirmar o responsável.", AppNotice.Kind.WARNING)
      return
    }
    // A wholly empty row is the user leaving the "Adicionar destinatário" placeholder untouched, so
    // it is dropped rather than reported as invalid. Partially filled rows still fail validation
    // below, because the update replaces the billing's whole recipient set.
    val draftRecipients = recipients.filterNot { it.isBlank }.map { it.domain() }
    val pix = pixKey.trim()
    val merchantName = pixMerchantName.trim()
    val merchantCity = pixMerchantCity.trim()
    pixRecipientRequiredMessage = when {
      pix.isEmpty() -> null
      merchantName.isEmpty() || merchantCity.isEmpty() ->
        "Informe o nome e a cidade do recebedor para usar uma chave PIX própria."

      else -> null
    }
    val draft = BillingDraft(
      name = name,
      description = billingDescription,
      owner = owner,
      items = items.mapIndexed { index, item -> item.domain(sortOrder = index) },
      pixOverride = if (pix.isEmpty()) {
        null
      } else {
        PixConfiguration(key = pix, merchantName = merchantName, merchantCity = merchantCity)
      },
      recipients = draftRecipients,
      replyTo = if (replyTo.isEmpty()) null else replyTo,
    )
    validationIssues.clear()
    validationIssues.addAll(draft.validate())
    if (validationIssues.isNotEmpty() || pixRecipientRequiredMessage != null) return

    saving = true
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

  LaunchedEffect(Unit) {
    organizations = try {
      app.dependencies.organizations.listOrganizations()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (_: Throwable) {
      emptyList()
    }
    organizationsLoaded = true
  }

  // Mirrors `.interactiveDismissDisabled(saving)`: a save in flight must not be backed out from.
  BackHandler(enabled = !saving) { onDismiss() }

  Scaffold(
    modifier = Modifier.rentivoPage(),
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = { Text(text = if (existing == null) "Nova cobrança" else "Editar cobrança") },
        colors = rentivoTopAppBarColors(),
        navigationIcon = {
          TextButton(onClick = onDismiss) {
            Text(text = "Cancelar", color = RentivoColors.ink)
          }
        },
        actions = {
          TextButton(
            onClick = { scope.launch { save() } },
            enabled = !saving && organizationsLoaded,
            modifier = Modifier.testTag("billing.form.save"),
          ) {
            Text(text = "Salvar", color = RentivoColors.emerald)
          }
        },
      )
    },
  ) { padding ->
    LazyColumn(
      modifier = Modifier.padding(padding).fillMaxSize(),
      contentPadding = PaddingValues(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
    ) {
      item {
        IdentificationSection(
          name = name,
          onNameChange = { name = it },
          description = billingDescription,
          onDescriptionChange = { billingDescription = it },
          ownerID = ownerID,
          onOwnerIDChange = { ownerID = it },
          ownerChoices = ownerChoices,
        )
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
          onReplyToChange = { replyTo = it },
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
  organizations: List<Organization>,
): List<BillingOwner> {
  val owners = mutableListOf<BillingOwner>(
    BillingOwner.User(id = currentUserID, name = "Pessoal")
  )
  if (currentOwner != null && owners.none { it.workspaceID == currentOwner.workspaceID }) {
    owners.add(currentOwner)
  }
  val existingIDs = owners.map { it.workspaceID }.toSet()
  owners.addAll(
    organizations
      .map { BillingOwner.Organization(id = it.id, name = it.name) }
      .filterNot { existingIDs.contains(it.workspaceID) }
  )
  return owners
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun IdentificationSection(
  name: String,
  onNameChange: (String) -> Unit,
  description: String,
  onDescriptionChange: (String) -> Unit,
  ownerID: WorkspaceID,
  onOwnerIDChange: (WorkspaceID) -> Unit,
  ownerChoices: List<BillingOwner>,
) {
  var expanded by remember { mutableStateOf(false) }
  val selectedName = ownerChoices.firstOrNull { it.workspaceID == ownerID }?.name.orEmpty()

  FormSection(title = "Identificação") {
    FormTextField(
      label = "Nome",
      value = name,
      onValueChange = onNameChange,
      modifier = Modifier.fillMaxWidth().testTag("billing.form.name"),
    )
    FormTextField(
      label = "Descrição",
      value = description,
      onValueChange = onDescriptionChange,
      singleLine = false,
      minLines = 2,
      maxLines = 4,
      modifier = Modifier.fillMaxWidth(),
    )
    ExposedDropdownMenuBox(
      expanded = expanded,
      onExpandedChange = { expanded = it },
    ) {
      FormTextField(
        label = "Responsável",
        value = selectedName,
        onValueChange = {},
        readOnly = true,
        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
        modifier = Modifier
          .fillMaxWidth()
          .menuAnchor(type = androidx.compose.material3.MenuAnchorType.PrimaryNotEditable),
      )
      ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ItemsSection(items: SnapshotStateList<EditableBillingItem>) {
  FormSection(
    title = "Itens recorrentes",
    footer = "Use valor zero para itens variáveis que serão preenchidos em cada fatura.",
  ) {
    items.forEachIndexed { index, item ->
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
        FormTextField(
          label = "Descrição do item",
          value = item.description,
          onValueChange = { items[index] = items[index].copy(description = it) },
          modifier = Modifier.fillMaxWidth(),
        )
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
          BillingItemType.entries.forEachIndexed { typeIndex, type ->
            SegmentedButton(
              selected = item.type == type,
              onClick = { items[index] = items[index].copy(type = type) },
              shape = SegmentedButtonDefaults.itemShape(
                index = typeIndex,
                count = BillingItemType.entries.size,
              ),
            ) {
              Text(text = type.label)
            }
          }
        }
        CurrencyCentavosField(
          label = "Valor do item",
          centavos = item.centavos,
          onCentavosChange = { items[index] = items[index].copy(centavos = it) },
          modifier = Modifier.fillMaxWidth(),
        )
        RowActions(
          canMoveUp = index > 0,
          canMoveDown = index < items.lastIndex,
          onMoveUp = { items.add(index - 1, items.removeAt(index)) },
          onMoveDown = { items.add(index + 1, items.removeAt(index)) },
          onDelete = { items.removeAt(index) },
        )
      }
    }
    IconTextButton(
      text = "Adicionar item",
      icon = Icons.Filled.AddCircle,
      onClick = { items.add(EditableBillingItem.blank()) },
    )
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
  FormSection(title = "PIX opcional") {
    FormTextField(
      label = "Chave PIX própria",
      value = key,
      onValueChange = onKeyChange,
      capitalization = KeyboardCapitalization.None,
      modifier = Modifier.fillMaxWidth().testTag("billing.form.pix.key"),
    )
    FormTextField(
      label = "Nome do recebedor",
      value = merchantName,
      onValueChange = onMerchantNameChange,
      modifier = Modifier.fillMaxWidth().testTag("billing.form.pix.merchantName"),
    )
    FormTextField(
      label = "Cidade do recebedor",
      value = merchantCity,
      onValueChange = onMerchantCityChange,
      capitalization = KeyboardCapitalization.Characters,
      modifier = Modifier.fillMaxWidth().testTag("billing.form.pix.merchantCity"),
    )
    Text(
      text = "Deixe em branco para herdar o PIX do responsável.",
      style = RentivoTypography.caption,
      color = RentivoColors.secondaryInk,
    )
  }
}

@Composable
private fun CommunicationSection(
  recipients: SnapshotStateList<EditableRecipient>,
  replyTo: String,
  onReplyToChange: (String) -> Unit,
) {
  FormSection(
    title = "Comunicação",
    footer = "Todos os destinatários listados recebem as comunicações desta cobrança.",
  ) {
    recipients.forEachIndexed { index, recipient ->
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
        FormTextField(
          label = "Nome do destinatário",
          value = recipient.name,
          onValueChange = { recipients[index] = recipients[index].copy(name = it) },
          modifier = Modifier.fillMaxWidth(),
        )
        FormTextField(
          label = "E-mail do destinatário",
          value = recipient.email,
          onValueChange = { recipients[index] = recipients[index].copy(email = it) },
          keyboardType = KeyboardType.Email,
          capitalization = KeyboardCapitalization.None,
          modifier = Modifier.fillMaxWidth(),
        )
        RowActions(
          canMoveUp = index > 0,
          canMoveDown = index < recipients.lastIndex,
          onMoveUp = { recipients.add(index - 1, recipients.removeAt(index)) },
          onMoveDown = { recipients.add(index + 1, recipients.removeAt(index)) },
          onDelete = { recipients.removeAt(index) },
        )
      }
    }
    IconTextButton(
      text = "Adicionar destinatário",
      icon = Icons.Filled.AddCircle,
      onClick = { recipients.add(EditableRecipient.blank()) },
      modifier = Modifier.testTag("billing.form.recipients.add"),
    )
    FormTextField(
      label = "Responder para",
      value = replyTo,
      onValueChange = onReplyToChange,
      keyboardType = KeyboardType.Email,
      capitalization = KeyboardCapitalization.None,
      modifier = Modifier.fillMaxWidth(),
    )
  }
}

@Composable
private fun ValidationSection(
  issues: List<ValidationIssue>,
  pixRecipientRequiredMessage: String?,
) {
  FormSection(title = "Revise os campos") {
    issues.forEach { issue ->
      ValidationRow(message = issue.message)
    }
    pixRecipientRequiredMessage?.let { message -> ValidationRow(message = message) }
  }
}

@Composable
private fun ValidationRow(message: String) {
  Row(
    modifier = Modifier.fillMaxWidth().testTag("billing.form.validation"),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = Icons.Filled.Error,
      contentDescription = null,
      tint = RentivoColors.coral,
    )
    Text(
      text = message,
      style = RentivoTypography.subheadline,
      color = RentivoColors.coral,
    )
  }
}

/** The iOS `Form` section: a titled card, optionally closed by explanatory footer copy. */
@Composable
private fun FormSection(
  title: String,
  footer: String? = null,
  content: @Composable () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Text(
      text = title,
      style = RentivoTypography.metadata,
      color = RentivoColors.secondaryInk,
    )
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) { content() }
    }
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
 * Reorder and delete controls for one editable row. The iOS form leans on `EditButton` plus
 * `onDelete`/`onMove`, which have no Compose equivalent, so each row carries its own controls.
 */
@Composable
private fun RowActions(
  canMoveUp: Boolean,
  canMoveDown: Boolean,
  onMoveUp: () -> Unit,
  onMoveDown: () -> Unit,
  onDelete: () -> Unit,
) {
  Row(horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
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
}

@Composable
private fun IconTextButton(
  text: String,
  icon: ImageVector,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  TextButton(onClick = onClick, modifier = modifier) {
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.emerald)
    Spacer(modifier = Modifier.width(RentivoSpacing.small))
    Text(text = text, color = RentivoColors.emerald)
  }
}

@Composable
private fun FormTextField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  singleLine: Boolean = true,
  minLines: Int = 1,
  maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
  readOnly: Boolean = false,
  keyboardType: KeyboardType = KeyboardType.Text,
  capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
  trailingIcon: @Composable (() -> Unit)? = null,
) {
  OutlinedTextField(
    value = value,
    onValueChange = onValueChange,
    modifier = modifier,
    label = { Text(text = label) },
    readOnly = readOnly,
    singleLine = singleLine,
    minLines = minLines,
    maxLines = maxLines,
    trailingIcon = trailingIcon,
    keyboardOptions = KeyboardOptions(
      keyboardType = keyboardType,
      capitalization = capitalization,
      autoCorrectEnabled = capitalization != KeyboardCapitalization.None,
    ),
    textStyle = RentivoTypography.body,
    shape = RoundedCornerShape(14.dp),
    colors = OutlinedTextFieldDefaults.colors(
      focusedBorderColor = RentivoColors.ink,
      unfocusedBorderColor = RentivoColors.ink,
      focusedContainerColor = RentivoColors.surface,
      unfocusedContainerColor = RentivoColors.surface,
      focusedTextColor = RentivoColors.ink,
      unfocusedTextColor = RentivoColors.ink,
      focusedLabelColor = RentivoColors.secondaryInk,
      unfocusedLabelColor = RentivoColors.secondaryInk,
    ),
  )
}
