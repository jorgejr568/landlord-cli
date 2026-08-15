package app.rentivo.features.bills

import android.content.Context
import android.net.Uri
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppModel
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.data.api.fileUploadFromUri
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoInlineTopBar
import app.rentivo.designsystem.RentivoListField
import app.rentivo.designsystem.RentivoSegmentedPicker
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.TopBarChip
import app.rentivo.designsystem.centavosFromInput
import app.rentivo.designsystem.displayText
import app.rentivo.designsystem.ptBRCount
import app.rentivo.domain.Attachment
import app.rentivo.domain.Bill
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.CommunicationContent
import app.rentivo.domain.CommunicationSaveScope
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.Expense
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.ExpenseInput
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money
import app.rentivo.domain.RecipientID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Port of `ios/Rentivo/Features/Bills/BillingOperationsViews.swift`: the operations a billing owns
 * beyond its bills — expenses, attachments, exports — plus the communication composer.
 */

/** The "Operações" card on the billing detail screen. Rows appear only where capabilities allow. */
@Composable
fun BillingOperationsLinks(
  billing: Billing,
  onOpenExpenses: () -> Unit,
  onOpenAttachments: () -> Unit,
  onOpenExport: () -> Unit,
) {
  val capabilities = billing.capabilities
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Operações", icon = Icons.Filled.GridView)
    RentivoCard {
      if (capabilities.canReadExpenses) {
        OperationRow(title = "Despesas", icon = Icons.Filled.Build, onClick = onOpenExpenses)
      }
      if (capabilities.canReadAttachments) {
        FormRowDivider()
        OperationRow(title = "Arquivos", icon = Icons.Filled.Folder, onClick = onOpenAttachments)
      }
      if (capabilities.canCreateExports) {
        FormRowDivider()
        OperationRow(
          title = "Exportar dados",
          icon = Icons.Filled.FileUpload,
          onClick = onOpenExport,
        )
      }
    }
  }
}

@Composable
private fun OperationRow(title: String, icon: ImageVector, onClick: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.ink)
    Text(
      text = title,
      style = RentivoTypography.subheadlineEmphasized,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Icon(
      imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
      contentDescription = null,
      tint = RentivoColors.secondaryInk,
    )
  }
}

/** The billing's expense ledger. Always blanks to Loading, as the iOS screen does. */
@Composable
fun ExpenseListScreen(billing: Billing, onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val canWrite = billing.capabilities.canWriteExpenses
  var state by remember { mutableStateOf<LoadState<List<Expense>>>(LoadState.Idle) }
  var showingAdd by remember { mutableStateOf(false) }
  var pendingDeletion by remember { mutableStateOf<Expense?>(null) }

  suspend fun load() {
    state = LoadState.Loading
    state = loadStateOf { app.dependencies.expenses.listExpenses(billingID = billing.id) }
  }

  suspend fun remove(expense: Expense) {
    app.mutate {
      app.dependencies.expenses.deleteExpense(billingID = billing.id, expenseID = expense.id)
      load()
    }
  }

  OperationScaffold(
    title = "Despesas",
    onBack = onBack,
    actions = {
      if (canWrite) {
        TopBarChip {
          IconButton(onClick = { showingAdd = true }) {
            Icon(imageVector = Icons.Filled.Add, contentDescription = "Adicionar")
          }
        }
      }
    },
  ) {
    PageStateView(state = state, retry = { scope.launch { load() } }) { expenses ->
      LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
      ) {
        item {
          SectionHeader(ptBRCount(expenses.size, singular = "despesa", plural = "despesas"))
        }
        items(expenses, key = { it.id.rawValue }) { expense ->
          SwipeToDelete(enabled = canWrite, onRequestDelete = { pendingDeletion = expense }) {
            ExpenseRow(expense)
          }
        }
      }
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  if (showingAdd) {
    ExpenseFormSheet(
      billingID = billing.id,
      onSaved = { load() },
      onDismiss = { showingAdd = false },
    )
  }

  pendingDeletion?.let { expense ->
    DestructiveDialog(
      title = "Excluir esta despesa?",
      message = "A despesa será removida permanentemente do registro desta cobrança.",
      confirmTitle = "Excluir despesa",
      onConfirm = {
        pendingDeletion = null
        scope.launch { remove(expense) }
      },
      onDismiss = { pendingDeletion = null },
    )
  }
}

@Composable
private fun ExpenseRow(expense: Expense) {
  // Flat: the row sits on a list of identical rows, where a second outline per row only adds noise.
  RentivoCard(flat = true) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Text(
        text = expense.description,
        style = RentivoTypography.cardTitle,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      MoneyText(money = expense.amount)
    }
    Spacer(modifier = Modifier.height(RentivoSpacing.small))
    Row(
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = Icons.Filled.LocalOffer,
        contentDescription = null,
        tint = RentivoColors.secondaryInk,
        modifier = Modifier.size(14.dp),
      )
      Text(
        text = expense.category.label,
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
  }
}

/** "Nova despesa": the full-screen form behind the expense list's add action. */
@Composable
private fun ExpenseFormSheet(
  billingID: BillingID,
  onSaved: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var description by remember { mutableStateOf("") }
  var centavos by remember { mutableIntStateOf(0) }
  var category by remember { mutableStateOf(ExpenseCategory.MAINTENANCE) }
  var incurredOn by remember { mutableStateOf(LocalDate.now()) }
  var showingDatePicker by remember { mutableStateOf(false) }

  suspend fun save() {
    app.mutate {
      app.dependencies.expenses.createExpense(
        billingID = billingID,
        description = ExpenseInput.normalizedDescription(description),
        category = category,
        incurredOn = DateOnly.from(incurredOn),
        amount = Money(centavos = centavos),
      )
      onSaved()
      onDismiss()
    }
  }

  // The title lives in the content, not the bar: iOS leaves this screen on the default (large)
  // display mode, so "Nova despesa" reads at display size above the form rather than inline.
  FormSheet(
    title = "",
    onDismiss = onDismiss,
    saveEnabled = ExpenseInput.isValidDescription(description) && centavos > 0,
    onSave = { scope.launch { save() } },
  ) {
    Text(
      text = "Nova despesa",
      style = RentivoTypography.display,
      color = RentivoColors.ink,
      modifier = Modifier.padding(bottom = RentivoSpacing.large),
    )
    RentivoCard {
      RentivoListField(
        value = description,
        onValueChange = { description = it },
        modifier = Modifier.padding(vertical = FormRowPadding),
        placeholder = "Descrição",
      )
      FormRowDivider()
      CurrencyRowField(
        centavos = centavos,
        onCentavosChange = { centavos = it },
        modifier = Modifier.padding(vertical = FormRowPadding),
      )
      FormRowDivider()
      PickerRow(
        label = "Categoria",
        options = ExpenseCategory.entries,
        selected = category,
        optionLabel = { it.label },
        onSelect = { category = it },
      )
      FormRowDivider()
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .clickable { showingDatePicker = true }
          .padding(vertical = RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = "Data",
          style = RentivoTypography.body,
          color = RentivoColors.ink,
          modifier = Modifier.weight(1f),
        )
        Text(
          text = DateOnly.from(incurredOn).displayFormatted,
          style = RentivoTypography.subheadlineEmphasized,
          color = RentivoColors.secondaryInk,
        )
      }
    }
  }

  if (showingDatePicker) {
    ExpenseDatePickerDialog(
      selected = incurredOn,
      onSelect = { incurredOn = it },
      onDismiss = { showingDatePicker = false },
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpenseDatePickerDialog(
  selected: LocalDate,
  onSelect: (LocalDate) -> Unit,
  onDismiss: () -> Unit,
) {
  val pickerState = rememberDatePickerState(
    initialSelectedDateMillis = selected.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
  )
  DatePickerDialog(
    onDismissRequest = onDismiss,
    confirmButton = {
      TextButton(
        onClick = {
          pickerState.selectedDateMillis?.let { millis ->
            onSelect(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate())
          }
          onDismiss()
        },
      ) { Text(text = "Confirmar") }
    },
    dismissButton = { TextButton(onClick = onDismiss) { Text(text = "Cancelar") } },
  ) {
    DatePicker(state = pickerState)
  }
}

/** The billing's uploaded documents. Always blanks to Loading, as the iOS screen does. */
@Composable
fun AttachmentListScreen(billing: Billing, onBack: () -> Unit) {
  val app = LocalAppModel.current
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  val canWrite = billing.capabilities.canWriteAttachments
  var state by remember { mutableStateOf<LoadState<List<Attachment>>>(LoadState.Idle) }
  var downloadedFile by remember { mutableStateOf<DownloadedFile?>(null) }
  var pendingDeletion by remember { mutableStateOf<Attachment?>(null) }

  suspend fun load() {
    state = LoadState.Loading
    state = loadStateOf { app.dependencies.attachments.listAttachments(billingID = billing.id) }
  }

  suspend fun add(uri: Uri) {
    app.mutate {
      val upload = fileUploadFromUri(context.contentResolver, uri)
      app.dependencies.attachments.addAttachment(billingID = billing.id, upload = upload)
      load()
      app.showNotice("Arquivo enviado.")
    }
  }

  suspend fun remove(attachment: Attachment) {
    app.mutate {
      app.dependencies.attachments.deleteAttachment(
        billingID = billing.id,
        attachmentID = attachment.id,
      )
      load()
    }
  }

  suspend fun download(attachment: Attachment) {
    app.mutate {
      downloadedFile = app.dependencies.downloads.downloadAttachment(
        billingID = billing.id,
        attachmentID = attachment.id,
      )
    }
  }

  val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    if (uri != null) scope.launch { add(uri) }
  }

  OperationScaffold(
    title = "Arquivos",
    onBack = onBack,
    actions = {
      if (canWrite) {
        TopBarChip {
          IconButton(onClick = { picker.launch(UploadMimeTypes) }) {
            Icon(imageVector = Icons.Filled.Add, contentDescription = "Adicionar")
          }
        }
      }
    },
  ) {
    PageStateView(state = state, retry = { scope.launch { load() } }) { attachments ->
      LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
      ) {
        item {
          SectionHeader(ptBRCount(attachments.size, singular = "arquivo", plural = "arquivos"))
        }
        items(attachments, key = { it.id.rawValue }) { attachment ->
          SwipeToDelete(enabled = canWrite, onRequestDelete = { pendingDeletion = attachment }) {
            AttachmentRow(
              attachment = attachment,
              onOpen = { scope.launch { download(attachment) } },
            )
          }
        }
      }
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  DownloadedFileSheet(file = downloadedFile, onDismiss = { downloadedFile = null })

  pendingDeletion?.let { attachment ->
    DestructiveDialog(
      title = "Excluir este arquivo?",
      message = "O arquivo será removido permanentemente e não poderá ser recuperado.",
      confirmTitle = "Excluir arquivo",
      onConfirm = {
        pendingDeletion = null
        scope.launch { remove(attachment) }
      },
      onDismiss = { pendingDeletion = null },
    )
  }
}

private val UploadMimeTypes = arrayOf("application/pdf", "image/*")

@Composable
private fun AttachmentRow(attachment: Attachment, onOpen: () -> Unit) {
  val context = LocalContext.current
  RentivoCard(flat = true) {
    Row(
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = Icons.Filled.Description,
        contentDescription = null,
        tint = RentivoColors.emerald,
      )
      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = attachment.name,
          style = RentivoTypography.cardTitle,
          color = RentivoColors.ink,
        )
        Text(
          text = fileSizeLabel(context = context, byteCount = attachment.byteCount),
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
        )
      }
      // A single-action menu behind an unlabeled "..." icon added an extra tap for no reason; this
      // is the only action, so it is a direct, accessibly-labeled button. The stroked circle is the
      // Android stand-in for SF Symbols' `arrow.down.circle`, whose ring is part of the glyph.
      IconButton(onClick = onOpen) {
        Box(
          modifier = Modifier
            .size(DownloadRingSize)
            .border(width = 1.5.dp, color = RentivoColors.emerald, shape = CircleShape),
          contentAlignment = Alignment.Center,
        ) {
          Icon(
            imageVector = Icons.Filled.Download,
            contentDescription = "Abrir",
            tint = RentivoColors.emerald,
            modifier = Modifier.size(DownloadGlyphSize),
          )
        }
      }
    }
  }
}

private val DownloadRingSize = 28.dp
private val DownloadGlyphSize = 16.dp

/**
 * Android's [Formatter] renders the kilobyte unit lowercase ("12 kB"), where iOS's
 * `ByteCountFormatter` renders "12 KB". Only that one unit differs — MB, GB and TB already come back
 * uppercase — so the two apps agree once it is normalized.
 */
private fun fileSizeLabel(context: Context, byteCount: Int): String =
  Formatter.formatFileSize(context, byteCount.toLong()).replace(oldValue = "kB", newValue = "KB")

/** Queues a server-side export of the billing's data. */
@Composable
fun ExportScreen(billing: Billing, onBack: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var format by remember { mutableStateOf("CSV") }

  suspend fun requestExport() {
    app.mutate {
      app.dependencies.exports.requestExport(billingID = billing.id, format = format.lowercase())
      app.showNotice("Exportação $format enfileirada.")
    }
  }

  OperationScaffold(title = "Exportar", onBack = onBack) {
    Column(
      modifier = Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
    ) {
      // The picker sits on a flat plate rather than a bordered card: a recessed groove inside a
      // 2dp-outlined box reads as two nested containers for one control.
      RentivoCard(flat = true, contentPadding = PaddingValues(RentivoSpacing.small)) {
        RentivoSegmentedPicker(
          options = ExportFormats,
          selectedIndex = ExportFormats.indexOf(format),
          onSelect = { index -> format = ExportFormats[index] },
        )
      }
      FormSection(header = "Conteúdo") {
        ContentRow(title = "Faturas", icon = Icons.Outlined.Description)
        FormRowDivider()
        ContentRow(title = "Despesas", icon = Icons.Outlined.Build)
        FormRowDivider()
        ContentRow(title = "Resumo financeiro", icon = Icons.Outlined.BarChart)
      }
      // The call to action is a block of its own, so it gets section spacing rather than the
      // large spacing that separates the picker from the content list.
      Spacer(modifier = Modifier.height(RentivoSpacing.section - RentivoSpacing.large))
      RentivoButton(
        text = "Solicitar exportação",
        onClick = { scope.launch { requestExport() } },
        color = RentivoColors.blue,
      )
    }
  }
}

private val ExportFormats = listOf("CSV", "XLSX")

/** The outlined glyph a `Label` in an iOS form row draws, sized to the row's 20pt symbol. */
private val ContentRowIconSize = 26.dp

@Composable
private fun ContentRow(title: String, icon: ImageVector) {
  Row(
    modifier = Modifier.padding(vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = RentivoColors.emerald,
      modifier = Modifier.size(ContentRowIconSize),
    )
    Text(text = title, style = RentivoTypography.body, color = RentivoColors.ink)
  }
}

/**
 * The e-mail composer for one bill: recipients, subject, Markdown body, and template save scope.
 */
@Composable
fun CommunicationComposerSheet(billing: Billing, bill: Bill, onDismiss: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val state = remember(billing, bill) { CommunicationComposerState(app, billing, bill) }

  LaunchedEffect(state.commType) {
    state.applyTemplateIfNeeded()
  }

  FullScreenSheet(onDismissRequest = onDismiss, dismissEnabled = !state.isSending) {
    Scaffold(
      containerColor = RentivoColors.paper,
      topBar = {
        SheetTopBar(
          title = "Enviar ${state.commType.label.lowercase()}",
          onCancel = onDismiss,
          cancelEnabled = !state.isSending,
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
        if (billing.recipients.isEmpty()) {
          FormSection {
            Text(
              text = "Nenhum destinatário cadastrado. Adicione destinatários na cobrança antes " +
                "de enviar.",
              style = RentivoTypography.body,
              color = RentivoColors.secondaryInk,
            )
          }
        } else {
          ComposerForm(state = state, onSend = { scope.launch { state.send(onDismiss) } })
        }
      }
    }
  }
}

@Composable
private fun ComposerForm(state: CommunicationComposerState, onSend: () -> Unit) {
  if (state.availableTypes.size > 1) {
    val typeLabels = state.availableTypes.map { it.label }
    RentivoCard(flat = true, contentPadding = PaddingValues(RentivoSpacing.small)) {
      RentivoSegmentedPicker(
        options = typeLabels,
        selectedIndex = state.availableTypes.indexOf(state.commType),
        onSelect = { index -> state.commType = state.availableTypes[index] },
      )
    }
  }

  FormSection(
    header = "Destinatários",
    footer = "Cada destinatário recebe um e-mail separado com o " +
      "${state.attachmentDescription} anexado.",
  ) {
    state.billing.recipients.forEachIndexed { position, recipient ->
      if (position > 0) FormRowDivider()
      Row(
        modifier = Modifier.padding(vertical = RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Column(modifier = Modifier.weight(1f)) {
          Text(
            text = recipient.name,
            style = RentivoTypography.subheadlineEmphasized,
            color = RentivoColors.ink,
          )
          Text(
            text = recipient.email,
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
        }
        Switch(
          checked = state.isSelected(recipient.id),
          onCheckedChange = { isOn -> state.setRecipient(recipient.id, isOn) },
        )
      }
    }
  }

  FormSection(
    header = "Mensagem",
    footer = "Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}.",
  ) {
    RentivoListField(
      value = state.subject,
      onValueChange = state::updateSubject,
      modifier = Modifier.padding(vertical = FormRowPadding),
      placeholder = "Assunto",
    )
    FormRowDivider()
    // The body's full title is a caption under the field rather than a label inside it: as a
    // floating label it stole a line of an already narrow multi-line editor, and it explains the
    // format rather than naming the value, which is what a footnote is for.
    RentivoListField(
      value = state.message,
      onValueChange = state::updateMessage,
      modifier = Modifier
        .padding(vertical = FormRowPadding)
        .heightIn(min = MessageFieldMinHeight),
      placeholder = "Corpo da mensagem",
      singleLine = false,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
    )
    Text(
      text = "Corpo (Markdown — HTML não é permitido)",
      style = RentivoTypography.caption,
      color = RentivoColors.secondaryInk,
    )
  }

  FormSection(footer = "O modelo salvo preenche automaticamente as próximas comunicações.") {
    PickerRow(
      label = "Salvar modelo",
      options = state.saveScopeOptions,
      selected = state.saveScope,
      optionLabel = state::saveScopeLabel,
      onSelect = { state.saveScope = it },
    )
  }

  RentivoButton(
    onClick = onSend,
    enabled = !state.sendDisabled,
    modifier = Modifier.testTag("comm.send"),
  ) {
    if (state.isSending) {
      CircularProgressIndicator(
        color = Color.White,
        strokeWidth = 2.dp,
        modifier = Modifier.size(18.dp),
      )
      Spacer(modifier = Modifier.width(RentivoSpacing.small))
    }
    Text(
      text = if (state.isSending) {
        "Enviando..."
      } else {
        "Enviar ${state.commType.label.lowercase()}"
      },
      style = RentivoTypography.cardTitle,
      color = Color.White,
    )
  }
}

/** The multi-line body editor's floor, i.e. the `lineLimit(5...12)` minimum the iOS composer sets. */
private val MessageFieldMinHeight = 110.dp

@Stable
private class CommunicationComposerState(
  private val app: AppModel,
  val billing: Billing,
  private val bill: Bill,
) {
  var commType by mutableStateOf(
    if (bill.capabilities.canSendInvoice) CommunicationType.BILL_READY else CommunicationType.PAYMENT_RECEIPT,
  )
  var subject by mutableStateOf(billing.template(commType)?.subject.orEmpty())
    private set
  var message by mutableStateOf(billing.template(commType)?.body.orEmpty())
    private set
  var saveScope by mutableStateOf<CommunicationSaveScope?>(null)
  var isSending by mutableStateOf(false)
    private set

  private var selectedRecipients by mutableStateOf(billing.recipients.map { it.id }.toSet())
  private var appliedTemplateType = commType

  val availableTypes: List<CommunicationType>
    get() = CommunicationType.entries.filter { type ->
      when (type) {
        CommunicationType.BILL_READY -> bill.capabilities.canSendInvoice
        CommunicationType.PAYMENT_RECEIPT ->
          bill.status == BillStatus.PAID && bill.capabilities.canSendRecibo
      }
    }

  val attachmentDescription: String
    get() = if (commType == CommunicationType.PAYMENT_RECEIPT) "recibo" else "PDF da fatura"

  /**
   * Defense in depth: the detail screen already disables the entry point while the PDF renders, but
   * a composer opened just before the render started must not attach a stale document.
   */
  val sendDisabled: Boolean
    get() = communicationSendIsDisabled(
      isSending = isSending,
      hasSelectedRecipients = selectedRecipients.isNotEmpty(),
      isRenderingPDF = bill.isRenderingPDF,
    ) || commType !in availableTypes

  val saveScopeOptions: List<CommunicationSaveScope?>
    get() = buildList {
      add(null)
      add(CommunicationSaveScope.BILLING)
      if (billing.capabilities.canEdit) add(CommunicationSaveScope.OWNER)
    }

  fun saveScopeLabel(scope: CommunicationSaveScope?): String = when (scope) {
    null -> "Não salvar como modelo"
    CommunicationSaveScope.BILLING -> "Salvar para esta cobrança"
    CommunicationSaveScope.OWNER -> if (billing.owner.isOrganization) {
      "Salvar para a organização"
    } else {
      "Salvar para minha conta"
    }
  }

  fun isSelected(id: RecipientID): Boolean = selectedRecipients.contains(id)

  fun setRecipient(id: RecipientID, isOn: Boolean) {
    selectedRecipients = if (isOn) selectedRecipients + id else selectedRecipients - id
  }

  fun updateSubject(value: String) {
    if (value == subject) return
    subject = value
  }

  fun updateMessage(value: String) {
    if (value == message) return
    message = value
  }

  /**
   * Re-prefills subject and body from the newly selected type's template.
   */
  fun applyTemplateIfNeeded() {
    if (appliedTemplateType == commType) return
    appliedTemplateType = commType
    val template = billing.template(commType)
    subject = template?.subject.orEmpty()
    message = template?.body.orEmpty()
  }

  suspend fun send(onDismiss: () -> Unit) {
    if (isSending) return
    if (selectedRecipients.isEmpty()) {
      app.showNotice("Selecione ao menos um destinatário.", AppNotice.Kind.WARNING)
      return
    }
    val validationMessage = CommunicationContent.validationMessage(subject = subject, message = message)
    if (validationMessage != null) {
      app.showNotice(validationMessage, AppNotice.Kind.WARNING)
      return
    }
    val normalizedSubject = CommunicationContent.normalizedSubject(subject)
    val normalizedMessage = CommunicationContent.normalizedMessage(message)
    isSending = true
    try {
      val orderedIDs = billing.recipients.map { it.id }.filter(selectedRecipients::contains)
      app.dependencies.communications.sendCommunication(
        billingID = billing.id,
        billID = bill.id,
        commType = commType,
        recipientIDs = orderedIDs,
        subject = normalizedSubject,
        message = normalizedMessage,
        acknowledgeWarning = false,
        saveScope = saveScope,
      )
      onDismiss()
      app.showNotice("Comunicação enfileirada para envio.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (failure: Throwable) {
      app.warn(failure)
    } finally {
      isSending = false
    }
  }
}

internal fun communicationSendIsDisabled(
  isSending: Boolean,
  hasSelectedRecipients: Boolean,
  isRenderingPDF: Boolean,
): Boolean = isSending || !hasSelectedRecipients || isRenderingPDF

// --- Shared building blocks -------------------------------------------------------------------

/** Every pushed operations screen renders the same paper page under the shared inline top bar. */
@Composable
private fun OperationScaffold(
  title: String,
  onBack: () -> Unit,
  actions: @Composable RowScope.() -> Unit = {},
  content: @Composable () -> Unit,
) {
  Scaffold(
    containerColor = RentivoColors.paper,
    topBar = { RentivoInlineTopBar(title = title, onBack = onBack, actions = actions) },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) { content() }
  }
}

/** The iOS sheet-with-navigation-stack form: full screen, "Cancelar" left and "Salvar" right. */
@Composable
private fun FormSheet(
  title: String,
  onDismiss: () -> Unit,
  saveEnabled: Boolean,
  onSave: () -> Unit,
  content: @Composable ColumnScope.() -> Unit,
) {
  FullScreenSheet(onDismissRequest = onDismiss) {
    Scaffold(
      containerColor = RentivoColors.paper,
      topBar = {
        SheetTopBar(title = title, onCancel = onDismiss) {
          TopBarChip {
            TextButton(onClick = onSave, enabled = saveEnabled) { Text(text = "Salvar") }
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
        content = content,
      )
    }
  }
}

/**
 * The navigation bar of a presented sheet: the same centered inline title and paper band as
 * [RentivoInlineTopBar], but with iOS's textual "Cancelar" in the leading slot instead of a back
 * chevron — a modal is dismissed, not popped, and the word is the shipped PT-BR copy.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SheetTopBar(
  title: String,
  onCancel: () -> Unit,
  cancelEnabled: Boolean = true,
  actions: @Composable RowScope.() -> Unit = {},
) {
  CenterAlignedTopAppBar(
    title = { Text(text = title, style = RentivoTypography.cardTitle, color = RentivoColors.ink) },
    navigationIcon = {
      TopBarChip {
        TextButton(onClick = onCancel, enabled = cancelEnabled) { Text(text = "Cancelar") }
      }
    },
    actions = actions,
    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
      containerColor = RentivoColors.paper,
      titleContentColor = RentivoColors.ink,
      navigationIconContentColor = RentivoColors.ink,
      actionIconContentColor = RentivoColors.emerald,
    ),
  )
}

/** Loads a list into the screen-local [LoadState], blanking to Loading on every attempt. */
private suspend fun <T> loadStateOf(fetch: suspend () -> List<T>): LoadState<List<T>> = try {
  val values = fetch()
  if (values.isEmpty()) LoadState.Empty else LoadState.Loaded(values)
} catch (cancellation: CancellationException) {
  throw cancellation
} catch (failure: Throwable) {
  LoadState.Failed(DemoError.from(failure))
}

/** Runs a mutation, downgrading failure to a warning banner rather than to a blanked screen. */
private suspend fun AppModel.mutate(block: suspend () -> Unit) {
  try {
    block()
  } catch (cancellation: CancellationException) {
    throw cancellation
  } catch (failure: Throwable) {
    warn(failure)
  }
}

/** An iOS `Form` section: caption header, card body, caption footer. */
@Composable
private fun FormSection(
  modifier: Modifier = Modifier,
  header: String? = null,
  footer: String? = null,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = modifier.fillMaxWidth(),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
  ) {
    if (header != null) SectionHeader(header)
    RentivoCard(content = content)
    if (footer != null) {
      Text(text = footer, style = RentivoTypography.caption, color = RentivoColors.secondaryInk)
    }
  }
}

/**
 * An iOS `Form` section header: plain secondary copy, no glyph. `subheadline` rather than the
 * smaller `metadata`, which set section titles a full step below the rows they introduce and let
 * them disappear against the page.
 *
 * `internal` so the bill form's sections read identically — the two screens are the same form
 * language and must not drift.
 */
@Composable
internal fun SectionHeader(title: String) {
  Text(text = title, style = RentivoTypography.subheadline, color = RentivoColors.secondaryInk)
}

/** The hairline between two rows of a form card, at the list separator's weight. */
@Composable
internal fun FormRowDivider() {
  HorizontalDivider(color = RentivoColors.separator)
}

/**
 * The vertical breathing room a borderless field needs to read as its own row, now that it no
 * longer brings an outlined container's padding with it.
 */
internal val FormRowPadding = RentivoSpacing.small

/**
 * The borderless twin of `CurrencyCentavosField`: the same centavos masking, but rendered as a bare
 * value on a form row instead of an outlined box with a floating label. The mask always renders an
 * amount, so iOS's "Valor em centavos" placeholder is never actually visible there — it survives
 * here as the accessibility label instead of becoming Android-only chrome.
 */
@Composable
internal fun CurrencyRowField(
  centavos: Int,
  onCentavosChange: (Int) -> Unit,
  modifier: Modifier = Modifier,
) {
  RentivoListField(
    value = displayText(centavos),
    onValueChange = { onCentavosChange(centavosFromInput(it)) },
    modifier = modifier.semantics { contentDescription = "Valor em centavos" },
    monospace = true,
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
  )
}

/** The iOS `Picker` inside a form row: the current value, a chevron, and a dropdown of options. */
@Composable
private fun <T> PickerRow(
  label: String,
  options: List<T>,
  selected: T,
  optionLabel: (T) -> String,
  onSelect: (T) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }
  Box {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .clickable { expanded = true }
        .padding(vertical = RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = label,
        style = RentivoTypography.body,
        color = RentivoColors.ink,
        modifier = Modifier.weight(1f),
      )
      Text(
        text = optionLabel(selected),
        style = RentivoTypography.subheadlineEmphasized,
        color = RentivoColors.secondaryInk,
      )
      Icon(
        imageVector = Icons.Filled.ArrowDropDown,
        contentDescription = null,
        tint = RentivoColors.secondaryInk,
      )
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
      options.forEach { option ->
        DropdownMenuItem(
          text = { Text(text = optionLabel(option)) },
          onClick = {
            expanded = false
            onSelect(option)
          },
        )
      }
    }
  }
}

/**
 * The iOS swipe action: swiping a row toward its start reveals the destructive affordance and asks
 * for confirmation. The swipe itself never commits — [onRequestDelete] opens the dialog and the row
 * settles back, so the deletion always goes through the confirmation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDelete(
  enabled: Boolean,
  onRequestDelete: () -> Unit,
  content: @Composable () -> Unit,
) {
  if (!enabled) {
    content()
    return
  }
  val state = rememberSwipeToDismissBoxState(
    confirmValueChange = { value ->
      if (value == SwipeToDismissBoxValue.EndToStart) onRequestDelete()
      false
    },
  )
  SwipeToDismissBox(
    state = state,
    enableDismissFromStartToEnd = false,
    backgroundContent = {
      Row(
        modifier = Modifier.fillMaxSize().padding(horizontal = RentivoSpacing.large),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Icon(
          imageVector = Icons.Filled.Delete,
          contentDescription = "Excluir",
          tint = RentivoColors.coral,
        )
      }
    },
    content = { content() },
  )
}

@Composable
private fun DestructiveDialog(
  title: String,
  message: String,
  confirmTitle: String,
  onConfirm: () -> Unit,
  onDismiss: () -> Unit,
) {
  AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text(text = title, style = RentivoTypography.title) },
    text = { Text(text = message, style = RentivoTypography.subheadline) },
    confirmButton = {
      TextButton(onClick = onConfirm) {
        Text(text = confirmTitle, color = RentivoColors.coral)
      }
    },
    dismissButton = { TextButton(onClick = onDismiss) { Text(text = "Cancelar") } },
    containerColor = RentivoColors.surface,
    titleContentColor = RentivoColors.ink,
    textContentColor = RentivoColors.secondaryInk,
  )
}

/** Failed mutations downgrade to a warning banner, never to a blanked screen. */
private fun AppModel.warn(failure: Throwable) {
  showNotice(DemoError.from(failure).message, AppNotice.Kind.WARNING)
}
