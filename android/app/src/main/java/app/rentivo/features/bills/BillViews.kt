package app.rentivo.features.bills

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Comment
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.data.api.fileUploadFromUri
import app.rentivo.designsystem.CurrencyCentavosField
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.StatusBadge
import app.rentivo.designsystem.capitalizedPTBR
import app.rentivo.designsystem.ptBRCount
import app.rentivo.domain.Bill
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillPDFPolling
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.ReferenceMonth
import app.rentivo.domain.ValidationIssue
import java.time.LocalDate
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

// MARK: - Form

/** The years the competência stepper accepts, mirroring the iOS `Stepper(in: 2024...2035)`. */
private val YEAR_RANGE = 2024..2035

private const val MILLIS_PER_DAY = 86_400_000L

/** A single editable row of the bill form, before it becomes a [BillLineItem]. */
private data class EditableBillLine(
  val id: BillLineItemID,
  val description: String,
  val centavos: Int,
  val kind: BillLineItemKind,
) {
  val domain: BillLineItem
    get() = BillLineItem(
      id = id,
      description = description,
      amount = Money(centavos = centavos),
      kind = kind,
    )

  companion object {
    fun from(line: BillLineItem): EditableBillLine = EditableBillLine(
      id = line.id,
      description = line.description,
      centavos = line.amount.centavos,
      kind = line.kind,
    )

    fun new(kind: BillLineItemKind): EditableBillLine = EditableBillLine(
      id = BillLineItemID(rawValue = UUID.randomUUID().toString()),
      description = "",
      centavos = 0,
      kind = kind,
    )

    /**
     * Seeds a line from an existing [BillingItem], preserving its original id (a server-issued
     * ULID). `createBill` keys `variable_amounts` by that original id, so minting a fresh client
     * UUID here would silently drop any user-edited variable amount for a new bill.
     */
    fun seededFrom(item: BillingItem, kind: BillLineItemKind): EditableBillLine = EditableBillLine(
      id = BillLineItemID(rawValue = item.id.rawValue),
      description = item.description,
      centavos = item.amount.centavos,
      kind = kind,
    )
  }
}

/**
 * Rewrites the line identified by [id], resolving its position at call time.
 *
 * The rows are rendered from a filtered view of the list, so a position captured while composing a
 * row stops pointing at that line as soon as any row above it is added or removed. Looking the id
 * up when the edit actually happens is what keeps a keystroke landing on the line the user is
 * typing into. A line that is gone by then is simply not written back.
 */
private fun MutableList<EditableBillLine>.updateLine(
  id: BillLineItemID,
  transform: (EditableBillLine) -> EditableBillLine,
) {
  val index = indexOfFirst { it.id == id }
  if (index >= 0) this[index] = transform(this[index])
}

/**
 * Creates or edits a bill. Port of the iOS `BillFormView`, presented as a full-screen surface with
 * the sheet's "Cancelar"/"Salvar" toolbar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BillFormSheet(
  billing: Billing,
  existing: Bill? = null,
  onSaved: suspend () -> Unit,
  onDismiss: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()

  val reference = remember(existing) {
    existing?.referenceMonth ?: LocalDate.now().let { today ->
      ReferenceMonth(year = today.year, month = today.monthValue)
    }
  }
  var year by remember { mutableIntStateOf(reference.year) }
  var month by remember { mutableIntStateOf(reference.month) }
  var dueDate by remember {
    mutableStateOf((existing?.dueDate ?: reference.defaultDueDate).resolvedDate())
  }
  /**
   * Set once the user touches the date picker. Until then the due date tracks the reference month
   * pickers, so changing the competência moves a still-default vencimento along with it.
   *
   * An existing bill's *stored* due date is authoritative and must never be recomputed from the
   * reference month. A bill with no stored date has nothing to protect, so it tracks the
   * competência like a new bill until the user touches the picker.
   */
  var dueDateEdited by remember { mutableStateOf(existing?.dueDate != null) }
  // A new bill always starts with a due date; an existing one keeps whatever the server has.
  var hasDueDate by remember { mutableStateOf(existing?.let { it.dueDate != null } ?: true) }
  var notes by remember { mutableStateOf(existing?.notes ?: "") }
  val lines = remember {
    mutableStateListOf<EditableBillLine>().apply {
      addAll(
        existing?.lineItems?.map(EditableBillLine::from)
          ?: billing.items.map { item ->
            EditableBillLine.seededFrom(
              item = item,
              kind = if (item.type == BillingItemType.FIXED) {
                BillLineItemKind.FIXED
              } else {
                BillLineItemKind.VARIABLE
              },
            )
          },
      )
    }
  }
  var issues by remember { mutableStateOf(emptyList<ValidationIssue>()) }
  var saving by remember { mutableStateOf(false) }
  var monthMenuExpanded by remember { mutableStateOf(false) }
  var showingDatePicker by remember { mutableStateOf(false) }

  fun syncDueDateWithReferenceMonth(nextYear: Int, nextMonth: Int) {
    if (dueDateEdited) return
    dueDate = ReferenceMonth(year = nextYear, month = nextMonth).defaultDueDate.resolvedDate()
  }

  /**
   * Writes through to [dueDate] while recording that the choice is now the user's. Reacting to a
   * plain change of `dueDate` can't do this — it would also fire for the programmatic writes in
   * [syncDueDateWithReferenceMonth] and immediately freeze the default.
   */
  fun selectDueDate(newValue: LocalDate) {
    dueDate = newValue
    dueDateEdited = true
  }

  suspend fun save() {
    val draft = BillDraft(
      billingID = billing.id,
      referenceMonth = ReferenceMonth(year = year, month = month),
      dueDate = if (hasDueDate) DateOnly.from(dueDate) else null,
      notes = notes,
      lineItems = lines.map { it.domain },
    )
    issues = draft.validate()
    if (issues.isNotEmpty()) return
    saving = true
    try {
      if (existing != null) {
        app.dependencies.bills.updateBill(
          billingID = billing.id,
          billID = existing.id,
          draft = draft,
        )
      } else {
        app.dependencies.bills.createBill(draft = draft)
      }
      onSaved()
      app.showNotice(
        if (existing == null) "Fatura criada como rascunho." else "Fatura atualizada.",
      )
      onDismiss()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    } finally {
      saving = false
    }
  }

  val total = lines.fold(Money.zero) { running, line -> running + Money(centavos = line.centavos) }

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      TopAppBar(
        title = { Text(text = if (existing == null) "Gerar fatura" else "Editar fatura") },
        navigationIcon = {
          TextButton(onClick = onDismiss) {
            Text(text = "Cancelar", color = RentivoColors.ink)
          }
        },
        actions = {
          TextButton(
            onClick = { scope.launch { save() } },
            enabled = !saving,
            modifier = Modifier.testTag("bill.form.save"),
          ) {
            Text(text = "Salvar", color = RentivoColors.emerald)
          }
        },
        colors = TopAppBarDefaults.topAppBarColors(
          containerColor = RentivoColors.surface,
          titleContentColor = RentivoColors.ink,
        ),
      )
    },
  ) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .verticalScroll(rememberScrollState())
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        SectionTitle(title = "Competência", icon = Icons.Filled.DateRange)
        RentivoCard {
          Box {
            FormRow(
              label = "Mês",
              modifier = Modifier
                .clickable { monthMenuExpanded = true }
                .testTag("bill.form.month"),
            ) {
              Text(
                text = monthName(year = year, month = month),
                style = RentivoTypography.subheadlineEmphasized,
                color = RentivoColors.ink,
              )
              Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = RentivoColors.secondaryInk,
              )
            }
            DropdownMenu(
              expanded = monthMenuExpanded,
              onDismissRequest = { monthMenuExpanded = false },
            ) {
              (1..12).forEach { candidate ->
                DropdownMenuItem(
                  text = { Text(text = monthName(year = year, month = candidate)) },
                  onClick = {
                    month = candidate
                    monthMenuExpanded = false
                    syncDueDateWithReferenceMonth(nextYear = year, nextMonth = candidate)
                  },
                )
              }
            }
          }
          FormRow(label = "Ano: $year", modifier = Modifier.testTag("bill.form.year")) {
            IconButton(
              onClick = {
                val next = year - 1
                year = next
                syncDueDateWithReferenceMonth(nextYear = next, nextMonth = month)
              },
              enabled = year > YEAR_RANGE.first,
            ) {
              Icon(imageVector = Icons.Filled.Remove, contentDescription = "Diminuir ano")
            }
            IconButton(
              onClick = {
                val next = year + 1
                year = next
                syncDueDateWithReferenceMonth(nextYear = next, nextMonth = month)
              },
              enabled = year < YEAR_RANGE.last,
            ) {
              Icon(imageVector = Icons.Filled.Add, contentDescription = "Aumentar ano")
            }
          }
        }
      }

      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        SectionTitle(title = "Vencimento", icon = Icons.Filled.Event)
        RentivoCard {
          FormRow(label = "Definir vencimento") {
            Switch(
              checked = hasDueDate,
              onCheckedChange = { hasDueDate = it },
              modifier = Modifier.testTag("bill.form.hasDueDate"),
            )
          }
          if (hasDueDate) {
            FormRow(
              label = "Data de vencimento",
              modifier = Modifier
                .clickable { showingDatePicker = true }
                .testTag("bill.form.dueDate"),
            ) {
              Text(
                text = DateOnly.from(dueDate).displayFormatted,
                style = RentivoTypography.subheadlineEmphasized,
                color = RentivoColors.ink,
              )
            }
            Text(
              text = "A competência é o mês de referência da fatura. O vencimento pode cair em outro mês.",
              style = RentivoTypography.caption,
              color = RentivoColors.secondaryInk,
            )
          }
        }
      }

      BillLineItemKind.entries.forEach { kind ->
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          SectionTitle(title = kind.sectionTitle, icon = Icons.Filled.Receipt)
          val kindLines = lines.filter { it.kind == kind }
          if (kindLines.isNotEmpty()) {
            RentivoCard {
              kindLines.forEachIndexed { position, line ->
                if (position > 0) HorizontalDivider(color = RentivoColors.secondaryInk)
                // `key` ties each row's composition — and with it the text field's cursor, focus and
                // IME state — to the line's identity rather than to its position, so deleting a row
                // above does not shift the one below into its slot. The callbacks resolve the index
                // at event time for the same reason: an index captured at composition time goes
                // stale the moment the list changes and would write to (or delete) another line.
                key(line.id.rawValue) {
                  BillLineRow(
                    line = line,
                    onDescriptionChange = { description ->
                      lines.updateLine(line.id) { it.copy(description = description) }
                    },
                    onCentavosChange = { centavos ->
                      lines.updateLine(line.id) { it.copy(centavos = centavos) }
                    },
                    // Fixed lines mirror the billing's own recurring items and aren't deletable
                    // here; only user-added variable/extra lines can be removed.
                    onDelete = if (kind == BillLineItemKind.FIXED) {
                      null
                    } else {
                      {
                        val index = lines.indexOfFirst { it.id == line.id }
                        if (index >= 0) lines.removeAt(index)
                      }
                    },
                  )
                }
              }
            }
          }
          if (kind == BillLineItemKind.EXTRA) {
            // Only extras get an "add new line" affordance here: extras are the server's mechanism
            // for ad-hoc per-bill lines. Variable items are defined by the billing (cobrança)
            // itself, seeded above from `billing.items`; the live store's `variable_amounts` only
            // accepts the billing's own ULID-keyed variable items, so a client-minted UUID for a
            // brand-new variable line would silently be dropped on save. Previously seeded variable
            // lines still render and remain editable and deletable above.
            OutlinedButton(
              onClick = { lines.add(EditableBillLine.new(kind = kind)) },
              modifier = Modifier.testTag("bill.form.addExtra"),
            ) {
              Icon(imageVector = Icons.Filled.AddCircle, contentDescription = null)
              Text(
                text = "Adicionar ${kind.actionLabel}",
                modifier = Modifier.padding(start = RentivoSpacing.small),
              )
            }
          }
        }
      }

      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        SectionTitle(title = "Observações", icon = Icons.AutoMirrored.Filled.Comment)
        OutlinedTextField(
          value = notes,
          onValueChange = { notes = it },
          modifier = Modifier
            .fillMaxWidth()
            .testTag("bill.form.notes"),
          label = { Text(text = "Mensagem opcional") },
          minLines = 3,
          maxLines = 6,
          keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        )
      }

      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        SectionTitle(title = "Total", icon = Icons.Filled.AttachMoney)
        RentivoCard { MoneyText(money = total) }
      }

      if (issues.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          SectionTitle(title = "Revise a fatura", icon = Icons.Filled.Error)
          RentivoCard {
            issues.forEach { issue ->
              IconLabel(
                text = issue.message,
                icon = Icons.Filled.Error,
                color = RentivoColors.coral,
              )
            }
          }
        }
      }
    }
  }

  if (showingDatePicker) {
    val pickerState = rememberDatePickerState(
      initialSelectedDateMillis = dueDate.toEpochDay() * MILLIS_PER_DAY,
    )
    DatePickerDialog(
      onDismissRequest = { showingDatePicker = false },
      confirmButton = {
        TextButton(
          onClick = {
            pickerState.selectedDateMillis?.let { millis ->
              selectDueDate(LocalDate.ofEpochDay(Math.floorDiv(millis, MILLIS_PER_DAY)))
            }
            showingDatePicker = false
          },
        ) {
          Text(text = "Confirmar")
        }
      },
      dismissButton = {
        TextButton(onClick = { showingDatePicker = false }) { Text(text = "Cancelar") }
      },
    ) {
      DatePicker(state = pickerState)
    }
  }
}

@Composable
private fun BillLineRow(
  line: EditableBillLine,
  onDescriptionChange: (String) -> Unit,
  onCentavosChange: (Int) -> Unit,
  onDelete: (() -> Unit)?,
) {
  Column(
    modifier = Modifier.padding(vertical = RentivoSpacing.small),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
  ) {
    OutlinedTextField(
      value = line.description,
      onValueChange = onDescriptionChange,
      modifier = Modifier.fillMaxWidth(),
      label = { Text(text = "Descrição") },
      singleLine = true,
      keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
    )
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      CurrencyCentavosField(
        label = "Valor em centavos",
        centavos = line.centavos,
        onCentavosChange = onCentavosChange,
        modifier = Modifier.weight(1f),
      )
      if (onDelete != null) {
        IconButton(onClick = onDelete) {
          Icon(
            imageVector = Icons.Filled.Delete,
            contentDescription = "Remover ${line.description}",
            tint = RentivoColors.coral,
          )
        }
      }
    }
  }
}

// MARK: - Detail

/**
 * One bill, with its composition, lifecycle transitions, generated documents and receipts. Port of
 * the iOS `BillDetailView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BillDetailScreen(
  billing: Billing,
  billId: BillID,
  onMutation: suspend () -> Unit,
  onBack: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()

  var state by remember { mutableStateOf<LoadState<Bill>>(LoadState.Idle) }
  // The billing arrives from the list, but its capabilities are re-read with every load so a
  // permission change is reflected without leaving the screen.
  var currentBilling by remember { mutableStateOf(billing) }
  var showingEdit by remember { mutableStateOf(false) }
  var showingCommunication by remember { mutableStateOf(false) }
  var downloadedFile by remember { mutableStateOf<DownloadedFile?>(null) }
  var confirmingDelete by remember { mutableStateOf(false) }
  /**
   * Bumped by `regenerate` so the poll loop restarts for the render it just enqueued, even when the
   * bill was already `pending`.
   */
  var pollGeneration by remember { mutableIntStateOf(0) }

  suspend fun load() {
    state = LoadState.Loading
    state = try {
      currentBilling = app.dependencies.billings.billing(id = billing.id)
      LoadState.Loaded(app.dependencies.bills.bill(billingID = billing.id, id = billId))
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      LoadState.Failed(DemoError.from(throwable))
    }
  }

  /**
   * Re-fetches the bill without ever entering [LoadState.Loading], so a poll tick can never replace
   * the screen the user is reading with `PageStateView`'s spinner.
   */
  suspend fun refreshQuietly() {
    try {
      val refreshedBilling = app.dependencies.billings.billing(id = billing.id)
      val refreshedBill = app.dependencies.bills.bill(billingID = billing.id, id = billId)
      currentCoroutineContext().ensureActive()
      currentBilling = refreshedBilling
      state = LoadState.Loaded(refreshedBill)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      // A failed silent refresh leaves the current state untouched; the loop retries on the next
      // tick. Reporting it would put a warning banner on the screen for a poll the user never
      // asked for.
    }
  }

  suspend fun refreshAll() {
    load()
    onMutation()
  }

  suspend fun transition(status: BillStatus) {
    try {
      app.dependencies.bills.transitionBill(
        billingID = billing.id,
        billID = billId,
        status = status,
      )
      refreshAll()
      app.showNotice("Fatura marcada como ${status.label.lowercase()}.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun deleteBill() {
    try {
      app.dependencies.bills.deleteBill(billingID = billing.id, billID = billId)
      onMutation()
      onBack()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun regenerate(bill: Bill) {
    try {
      val queued = app.dependencies.bills.regenerateBill(billingID = billing.id, billID = bill.id)
      // The 202 body is the bill *summary* (no receipts), so merging only its render/status
      // metadata flips the screen to "Renderizando…" without a round trip and without blanking the
      // receipt list; bumping the generation restarts the poll loop.
      state = LoadState.Loaded(bill.applyingRenderMetadata(updated = queued))
      pollGeneration += 1
      onMutation()
      app.showNotice("Documento enfileirado para regeneração.")
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun downloadInvoice() {
    try {
      downloadedFile = app.dependencies.downloads.downloadInvoice(
        billingID = billing.id,
        billID = billId,
      )
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  suspend fun downloadRecibo() {
    try {
      downloadedFile = app.dependencies.downloads.downloadRecibo(
        billingID = billing.id,
        billID = billId,
      )
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }
  LaunchedEffect(app.dataRevision, pollGeneration, state.value?.isRenderingPDF == true) {
    while (BillPDFPolling.shouldPoll(state.value)) {
      delay(BillPDFPolling.INTERVAL_MILLIS)
      refreshQuietly()
    }
  }

  val loaded = state.value
  BackHandler(enabled = showingEdit || showingCommunication) {
    showingEdit = false
    showingCommunication = false
  }

  when {
    showingEdit && loaded != null -> BillFormSheet(
      billing = currentBilling,
      existing = loaded,
      onSaved = { refreshAll() },
      onDismiss = { showingEdit = false },
    )

    showingCommunication && loaded != null -> CommunicationComposerSheet(
      billing = currentBilling,
      bill = loaded,
      onDismiss = { showingCommunication = false },
    )

    else -> Scaffold(
      modifier = Modifier.fillMaxSize(),
      containerColor = RentivoColors.paper,
      topBar = {
        TopAppBar(
          title = { Text(text = "Fatura") },
          navigationIcon = {
            IconButton(onClick = onBack) {
              Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Voltar",
              )
            }
          },
          actions = {
            if (loaded?.status == BillStatus.DRAFT && currentBilling.capabilities.canManageBills) {
              TextButton(
                onClick = { showingEdit = true },
                modifier = Modifier.testTag("bill.edit"),
              ) {
                Text(text = "Editar", color = RentivoColors.emerald)
              }
            }
          },
          colors = TopAppBarDefaults.topAppBarColors(
            containerColor = RentivoColors.surface,
            titleContentColor = RentivoColors.ink,
          ),
        )
      },
    ) { padding ->
      PageStateView(
        state = state,
        modifier = Modifier.padding(padding),
        retry = { scope.launch { load() } },
      ) { bill ->
        BillDetailContent(
          billing = currentBilling,
          bill = bill,
          modifier = Modifier.padding(padding),
          onTransition = { status -> scope.launch { transition(status) } },
          onOpenInvoice = { scope.launch { downloadInvoice() } },
          onOpenRecibo = { scope.launch { downloadRecibo() } },
          onRegenerate = { scope.launch { regenerate(bill) } },
          onCompose = { showingCommunication = true },
          onDelete = { confirmingDelete = true },
          onMutation = { refreshAll() },
        )
      }
    }
  }

  DownloadedFileSheet(file = downloadedFile, onDismiss = { downloadedFile = null })

  if (confirmingDelete) {
    AlertDialog(
      onDismissRequest = { confirmingDelete = false },
      title = { Text(text = "Excluir esta fatura?") },
      confirmButton = {
        TextButton(
          onClick = {
            confirmingDelete = false
            scope.launch { deleteBill() }
          },
        ) {
          Text(text = "Excluir fatura", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingDelete = false }) { Text(text = "Cancelar") }
      },
      containerColor = RentivoColors.surface,
    )
  }
}

@Composable
private fun BillDetailContent(
  billing: Billing,
  bill: Bill,
  modifier: Modifier = Modifier,
  onTransition: (BillStatus) -> Unit,
  onOpenInvoice: () -> Unit,
  onOpenRecibo: () -> Unit,
  onRegenerate: () -> Unit,
  onCompose: () -> Unit,
  onDelete: () -> Unit,
  onMutation: suspend () -> Unit,
) {
  Column(
    modifier = modifier
      .fillMaxSize()
      .verticalScroll(rememberScrollState())
      .padding(RentivoSpacing.page),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
  ) {
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        Row(verticalAlignment = Alignment.Top) {
          Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
          ) {
            Text(
              text = billing.name,
              style = RentivoTypography.subheadlineEmphasized,
              color = RentivoColors.secondaryInk,
            )
            Text(
              text = bill.referenceMonth.label.capitalizedPTBR(),
              style = RentivoTypography.title,
              color = RentivoColors.ink,
            )
          }
          StatusBadge(status = bill.status)
        }
        MoneyText(money = bill.effectiveTotal)
        bill.dueDate?.let { dueDate ->
          IconLabel(
            text = "Vencimento: ${dueDate.displayFormatted}",
            icon = Icons.Filled.CalendarMonth,
            style = RentivoTypography.subheadline,
          )
        }
        bill.paidAt?.let { paidAt ->
          IconLabel(
            text = "Pago em ${paidAt.displayFormatted}",
            icon = Icons.Filled.CheckCircle,
            color = RentivoColors.emerald,
            style = RentivoTypography.subheadlineEmphasized,
          )
        }
      }
    }

    BillLineItemsSection(bill = bill)

    if (billing.capabilities.canManageBills) {
      BillLifecycleSection(bill = bill, onTransition = onTransition)
    } else {
      IconLabel(
        text = "Ciclo disponível somente para quem pode gerenciar faturas.",
        icon = Icons.Filled.Visibility,
        color = RentivoColors.secondaryInk,
        style = RentivoTypography.caption,
      )
    }

    BillDocumentSection(
      bill = bill,
      canManageBills = billing.capabilities.canManageBills,
      onOpenInvoice = onOpenInvoice,
      onOpenRecibo = onOpenRecibo,
      onRegenerate = onRegenerate,
    )

    ReceiptManagerSection(
      billingID = billing.id,
      bill = bill,
      canWrite = billing.capabilities.canUploadBillReceipts,
      onMutation = onMutation,
    )

    if (billing.capabilities.canManageBills) {
      RentivoButton(
        onClick = onCompose,
        enabled = !bill.isRenderingPDF,
        modifier = Modifier.testTag("bill.communicate"),
      ) {
        Icon(
          imageVector = Icons.AutoMirrored.Filled.Send,
          contentDescription = null,
          tint = Color.White,
        )
        Text(
          text = "Enviar comunicação",
          style = RentivoTypography.cardTitle,
          color = Color.White,
          modifier = Modifier.padding(start = RentivoSpacing.small),
        )
      }
      OutlinedButton(
        onClick = onDelete,
        modifier = Modifier
          .fillMaxWidth()
          .testTag("bill.delete"),
      ) {
        Icon(
          imageVector = Icons.Filled.Delete,
          contentDescription = null,
          tint = RentivoColors.coral,
        )
        Text(
          text = "Excluir fatura",
          color = RentivoColors.coral,
          modifier = Modifier.padding(start = RentivoSpacing.small),
        )
      }
    }
  }
}

@Composable
private fun BillLineItemsSection(bill: Bill) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Composição", icon = Icons.Filled.Receipt)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        bill.lineItems.forEach { line ->
          Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
              Text(
                text = line.description,
                style = RentivoTypography.subheadlineEmphasized,
                color = RentivoColors.ink,
              )
              Text(
                text = line.kind.sectionTitle,
                style = RentivoTypography.caption,
                color = RentivoColors.secondaryInk,
              )
            }
            MoneyText(money = line.amount)
          }
        }
        if (bill.notes.isNotEmpty()) {
          HorizontalDivider(color = RentivoColors.secondaryInk)
          Text(
            text = bill.notes,
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
        }
      }
    }
  }
}

@Composable
private fun BillLifecycleSection(bill: Bill, onTransition: (BillStatus) -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Ciclo da fatura", icon = Icons.Filled.Autorenew)
    // Prefer the server-authoritative transitions for this specific bill (`available_transitions`)
    // over the local `BillStatus` state machine, when the API supplies them.
    if (bill.effectiveTransitions.isEmpty()) {
      IconLabel(
        text = "Esta fatura está em um estado final.",
        icon = Icons.Filled.CheckCircle,
        color = RentivoColors.secondaryInk,
      )
    } else {
      bill.effectiveTransitions.sortedBy { it.wire }.forEach { status ->
        RentivoButton(
          onClick = { onTransition(status) },
          modifier = Modifier.testTag("bill.transition.${status.wire}"),
        ) {
          Icon(imageVector = status.icon, contentDescription = null, tint = Color.White)
          Text(
            text = "Marcar como ${status.label.lowercase()}",
            style = RentivoTypography.cardTitle,
            color = Color.White,
            modifier = Modifier.padding(start = RentivoSpacing.small),
          )
        }
      }
    }
  }
}

@Composable
private fun BillDocumentSection(
  bill: Bill,
  canManageBills: Boolean,
  onOpenInvoice: () -> Unit,
  onOpenRecibo: () -> Unit,
  onRegenerate: () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Documento", icon = Icons.Filled.PictureAsPdf)
    when (bill.pdfRenderStatus) {
      PDFRenderStatus.PENDING -> Row(
        modifier = Modifier.testTag("bill.pdf.rendering"),
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        IconLabel(
          text = "Renderizando…",
          icon = Icons.Filled.Schedule,
          color = RentivoColors.secondaryInk,
          style = RentivoTypography.caption,
        )
        CircularProgressIndicator(
          modifier = Modifier.size(16.dp),
          color = RentivoColors.emerald,
          strokeWidth = 2.dp,
        )
      }

      PDFRenderStatus.FAILED -> IconLabel(
        text = "Falha no PDF",
        icon = Icons.Filled.Warning,
        color = RentivoColors.coral,
        style = RentivoTypography.caption,
        modifier = Modifier.testTag("bill.pdf.failed"),
      )

      PDFRenderStatus.SUCCEEDED, null -> Unit
    }
    RentivoButton(
      onClick = onOpenInvoice,
      color = RentivoColors.blue,
      enabled = !bill.isRenderingPDF && bill.capabilities.canDownloadInvoice,
      modifier = Modifier.testTag("bill.pdf.open"),
    ) {
      Icon(imageVector = Icons.Filled.FindInPage, contentDescription = null, tint = Color.White)
      Text(
        text = "Abrir fatura em PDF",
        style = RentivoTypography.cardTitle,
        color = Color.White,
        modifier = Modifier.padding(start = RentivoSpacing.small),
      )
    }
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    ) {
      // Regenerating stays available while a render is pending: a re-trigger supersedes the
      // in-flight render server-side.
      OutlinedButton(
        onClick = onRegenerate,
        enabled = canManageBills,
        modifier = Modifier
          .weight(1f)
          .testTag("bill.pdf.regenerate"),
      ) {
        Text(text = "Regenerar documento")
      }
      if (bill.status == BillStatus.PAID) {
        // Gated on the pending render alone: the app opens `GET .../recibo`, which renders the
        // recibo inline when no file is stored yet, so `canDownloadRecibo` (a stored-file gate)
        // would disable a button the endpoint would have served.
        OutlinedButton(
          onClick = onOpenRecibo,
          enabled = !bill.isRenderingPDF,
          modifier = Modifier
            .weight(1f)
            .testTag("bill.recibo.open"),
        ) {
          Text(text = "Abrir recibo")
        }
      }
    }
    if (bill.isRenderingPDF) {
      Text(
        text = "Os documentos ficam disponíveis assim que a geração terminar.",
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
  }
}

// MARK: - Receipts

/** Port of the iOS `ReceiptManagerView`: lists, opens, uploads, reorders and deletes receipts. */
@Composable
private fun ReceiptManagerSection(
  billingID: BillingID,
  bill: Bill,
  canWrite: Boolean,
  onMutation: suspend () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val resolver = LocalContext.current.contentResolver
  var downloadedFile by remember { mutableStateOf<DownloadedFile?>(null) }
  var pendingDeletion by remember { mutableStateOf<Receipt?>(null) }
  var openMenuFor by remember { mutableStateOf<ReceiptID?>(null) }

  suspend fun report(throwable: Throwable) {
    app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
  }

  val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    if (uri == null) return@rememberLauncherForActivityResult
    scope.launch {
      try {
        val upload = fileUploadFromUri(resolver = resolver, uri = uri)
        app.dependencies.bills.addReceipt(
          billingID = billingID,
          billID = bill.id,
          upload = upload,
        )
        onMutation()
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        report(throwable)
      }
    }
  }

  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      SectionTitle(title = "Comprovantes", icon = Icons.Filled.AttachFile)
      if (bill.receipts.isNotEmpty()) {
        Text(
          text = ptBRCount(bill.receipts.size, "comprovante", "comprovantes"),
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
          modifier = Modifier
            .weight(1f)
            .padding(start = RentivoSpacing.small),
        )
      }
    }
    if (bill.receipts.isEmpty()) {
      Text(
        text = "Nenhum comprovante anexado.",
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
    } else {
      RentivoCard {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          bill.receipts.forEach { receipt ->
            Row(verticalAlignment = Alignment.CenterVertically) {
              IconLabel(
                text = receipt.name,
                icon = Icons.AutoMirrored.Filled.InsertDriveFile,
                style = RentivoTypography.subheadline,
                modifier = Modifier.weight(1f),
              )
              Box {
                IconButton(onClick = { openMenuFor = receipt.id }) {
                  Icon(
                    imageVector = Icons.Filled.MoreVert,
                    contentDescription = "Mais opções para ${receipt.name}",
                    tint = RentivoColors.ink,
                  )
                }
                DropdownMenu(
                  expanded = openMenuFor == receipt.id,
                  onDismissRequest = { openMenuFor = null },
                ) {
                  DropdownMenuItem(
                    text = { Text(text = "Abrir") },
                    onClick = {
                      openMenuFor = null
                      scope.launch {
                        try {
                          downloadedFile = app.dependencies.downloads.downloadReceipt(
                            billingID = billingID,
                            billID = bill.id,
                            receiptID = receipt.id,
                          )
                        } catch (cancellation: CancellationException) {
                          throw cancellation
                        } catch (throwable: Throwable) {
                          report(throwable)
                        }
                      }
                    },
                  )
                  if (canWrite) {
                    DropdownMenuItem(
                      text = { Text(text = "Excluir", color = RentivoColors.coral) },
                      onClick = {
                        openMenuFor = null
                        pendingDeletion = receipt
                      },
                    )
                  }
                }
              }
            }
          }
          // Drag-to-reorder would need these rows hosted in a reorderable list, but this section
          // renders inside a `RentivoCard` on a scrolling column. Kept as an explicit action
          // instead of restructuring the whole detail screen's layout.
          if (bill.receipts.size > 1 && canWrite) {
            OutlinedButton(
              onClick = {
                scope.launch {
                  try {
                    app.dependencies.bills.reorderReceipts(
                      billingID = billingID,
                      billID = bill.id,
                      receiptIDs = bill.receipts.map { it.id }.reversed(),
                    )
                    onMutation()
                  } catch (cancellation: CancellationException) {
                    throw cancellation
                  } catch (throwable: Throwable) {
                    report(throwable)
                  }
                }
              },
              modifier = Modifier.testTag("bill.receipts.reverse"),
            ) {
              Text(text = "Inverter ordem")
            }
          }
        }
      }
    }
    if (canWrite) {
      OutlinedButton(
        onClick = { picker.launch(arrayOf("application/pdf", "image/*")) },
        modifier = Modifier.testTag("bill.receipts.add"),
      ) {
        Icon(imageVector = Icons.Filled.Add, contentDescription = null)
        Text(
          text = "Adicionar comprovante",
          modifier = Modifier.padding(start = RentivoSpacing.small),
        )
      }
    }
  }

  DownloadedFileSheet(file = downloadedFile, onDismiss = { downloadedFile = null })

  pendingDeletion?.let { receipt ->
    AlertDialog(
      onDismissRequest = { pendingDeletion = null },
      title = { Text(text = "Excluir este comprovante?") },
      text = { Text(text = "O comprovante será removido permanentemente desta fatura.") },
      confirmButton = {
        TextButton(
          onClick = {
            pendingDeletion = null
            scope.launch {
              try {
                app.dependencies.bills.deleteReceipt(
                  billingID = billingID,
                  billID = bill.id,
                  receiptID = receipt.id,
                )
                onMutation()
              } catch (cancellation: CancellationException) {
                throw cancellation
              } catch (throwable: Throwable) {
                report(throwable)
              }
            }
          },
        ) {
          Text(text = "Excluir comprovante", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { pendingDeletion = null }) { Text(text = "Cancelar") }
      },
      containerColor = RentivoColors.surface,
    )
  }
}

// MARK: - Shared pieces

/** The Compose analog of SwiftUI's `Label(title, systemImage:)`. */
@Composable
private fun IconLabel(
  text: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.ink,
  style: TextStyle = RentivoTypography.body,
) {
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = color)
    Text(text = text, style = style, color = color)
  }
}

/** A labelled form row: the label on the leading edge, the control on the trailing edge. */
@Composable
private fun FormRow(
  label: String,
  modifier: Modifier = Modifier,
  content: @Composable () -> Unit,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(text = label, style = RentivoTypography.body, color = RentivoColors.ink)
    Row(verticalAlignment = Alignment.CenterVertically) { content() }
  }
}

/** The month name alone, capitalized: "agosto de 2026" -> "Agosto". */
private fun monthName(year: Int, month: Int): String =
  ReferenceMonth(year = year, month = month).label.substringBefore(" de ").capitalizedPTBR()

private val BillLineItemKind.sectionTitle: String
  get() = when (this) {
    BillLineItemKind.FIXED -> "Itens fixos"
    BillLineItemKind.VARIABLE -> "Itens variáveis"
    BillLineItemKind.EXTRA -> "Itens extras"
  }

private val BillLineItemKind.actionLabel: String
  get() = when (this) {
    BillLineItemKind.FIXED -> "item fixo"
    BillLineItemKind.VARIABLE -> "valor variável"
    BillLineItemKind.EXTRA -> "item extra"
  }

private val BillStatus.icon: ImageVector
  get() = when (this) {
    BillStatus.DRAFT -> Icons.Filled.Edit
    BillStatus.PUBLISHED -> Icons.Filled.Campaign
    BillStatus.SENT -> Icons.AutoMirrored.Filled.Send
    BillStatus.PAID -> Icons.Filled.VerifiedUser
    BillStatus.CANCELLED -> Icons.Filled.Cancel
    BillStatus.DELAYED_PAYMENT -> Icons.Filled.Schedule
  }
