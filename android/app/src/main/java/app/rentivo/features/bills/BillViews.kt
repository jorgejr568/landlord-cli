package app.rentivo.features.bills

import android.content.pm.PackageManager
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.data.ReceiptCaptureStore
import app.rentivo.data.api.fileUploadFromCapture
import app.rentivo.data.api.fileUploadFromUri
import app.rentivo.data.api.prepareReceiptUpload
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.IconLabel
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.MutationGate
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoInlineTopBar
import app.rentivo.designsystem.RentivoListDivider
import app.rentivo.designsystem.RentivoListField
import app.rentivo.designsystem.RentivoListGroup
import app.rentivo.designsystem.RentivoProminentButton
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTonalButton
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.StatusBadge
import app.rentivo.designsystem.TopBarChip
import app.rentivo.designsystem.capitalizedPTBR
import app.rentivo.designsystem.ptBRCount
import app.rentivo.domain.Bill
import app.rentivo.domain.BillCapabilities
import app.rentivo.domain.BillCommunication
import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillFormEditRule
import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillPDFPolling
import app.rentivo.domain.BillStatus
import app.rentivo.domain.BillTransition
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.FileUpload
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money
import app.rentivo.domain.PDFRenderStatus
import app.rentivo.domain.Receipt
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.ReferenceMonth
import app.rentivo.domain.ValidationIssue
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

// MARK: - Form

/** The years the competência stepper accepts, mirroring the iOS `Stepper(in: 2024...2035)`. */
private val YEAR_RANGE = 2024..2035

private val BILL_HISTORY_DATE_FORMAT = DateTimeFormatter
  .ofPattern("dd/MM/yyyy HH:mm")
  .withZone(ZoneId.systemDefault())

private const val MILLIS_PER_DAY = 86_400_000L

/** A single editable row of the bill form, before it becomes a [BillLineItem]. */
private data class EditableBillLine(
  val id: BillLineItemID,
  val description: String,
  val centavos: Long,
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
      centavos = 0L,
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
  val initialDueDate = remember(existing, reference) {
    (existing?.dueDate ?: reference.defaultDueDate).resolvedDate()
  }
  val initialHasDueDate = existing?.let { it.dueDate != null } ?: true
  val initialLines = remember(existing, billing) {
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
      }
  }
  var year by remember { mutableIntStateOf(reference.year) }
  var month by remember { mutableIntStateOf(reference.month) }
  var dueDate by remember {
    mutableStateOf(initialDueDate)
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
  var hasDueDate by remember { mutableStateOf(initialHasDueDate) }
  var notes by remember { mutableStateOf(existing?.notes ?: "") }
  val lines = remember {
    mutableStateListOf<EditableBillLine>().apply {
      addAll(initialLines)
    }
  }
  var issues by remember { mutableStateOf(emptyList<ValidationIssue>()) }
  var saving by remember { mutableStateOf(false) }
  var monthMenuExpanded by remember { mutableStateOf(false) }
  var showingDatePicker by remember { mutableStateOf(false) }
  var confirmingDiscard by remember { mutableStateOf(false) }
  val editRule = BillFormEditRule(isEditing = existing != null)
  val hasUnsavedChanges = year != reference.year || month != reference.month ||
    dueDate != initialDueDate || hasDueDate != initialHasDueDate || notes != existing?.notes.orEmpty() ||
    lines.toList() != initialLines

  fun requestDismiss() {
    if (saving) return
    if (hasUnsavedChanges) confirmingDiscard = true else onDismiss()
  }

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

  fun submit() {
    if (saving) return
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
    scope.launch {
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
  }

  val total = lines.fold(Money.zero) { running, line -> running + Money(centavos = line.centavos) }

  // A `Dialog`-backed sheet, not an in-tab surface: the form is presented modally on iOS, and only
  // a dialog can rise over the floating tab bar the way that sheet does. Dismissal is gated while a
  // save is in flight, so back cannot abandon a request the server is already handling.
  FullScreenSheet(onDismissRequest = ::requestDismiss, dismissEnabled = !saving) {
    Scaffold(
      modifier = Modifier.fillMaxSize(),
      containerColor = RentivoColors.paper,
      topBar = {
        SheetTopBar(
          title = if (existing == null) "Gerar fatura" else "Editar fatura",
          onCancel = ::requestDismiss,
          cancelEnabled = !saving,
        ) {
          TopBarChip {
            TextButton(
              onClick = ::submit,
              enabled = !saving,
              modifier = Modifier.testTag("bill.form.save"),
            ) {
              Text(text = "Salvar", color = RentivoColors.emerald)
            }
          }
        }
      },
    ) { padding ->
      LazyColumn(
        modifier = Modifier
          .fillMaxSize()
          .padding(padding)
          .imePadding(),
        contentPadding = PaddingValues(RentivoSpacing.page),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
      ) {
        item(key = "reference") { FormSectionColumn(header = "Competência") {
          RentivoListGroup {
            if (!editRule.canEditReferenceMonth) {
              FormRow(label = "Competência") {
                Text(
                  text = reference.displayFormatted,
                  style = RentivoTypography.subheadlineEmphasized,
                  color = RentivoColors.secondaryInk,
                  modifier = Modifier.testTag("bill.form.referenceMonth.readonly"),
                )
              }
            } else Box {
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
            if (editRule.canEditReferenceMonth) {
              RentivoListDivider()
              FormRow(label = "Ano: $year", modifier = Modifier.testTag("bill.form.year")) {
                YearStepper(
                  canDecrease = year > YEAR_RANGE.first,
                  canIncrease = year < YEAR_RANGE.last,
                  onDecrease = {
                    val next = year - 1
                    year = next
                    syncDueDateWithReferenceMonth(nextYear = next, nextMonth = month)
                  },
                  onIncrease = {
                    val next = year + 1
                    year = next
                    syncDueDateWithReferenceMonth(nextYear = next, nextMonth = month)
                  },
                )
              }
            }
          }
        } }

        item(key = "due-date") { FormSectionColumn(header = "Vencimento") {
          RentivoListGroup {
            FormRow(label = "Definir vencimento") {
              Switch(
                checked = hasDueDate,
                onCheckedChange = { hasDueDate = it },
                modifier = Modifier.testTag("bill.form.hasDueDate"),
              )
            }
            if (hasDueDate) {
              RentivoListDivider()
              FormRow(
                label = "Data de vencimento",
                modifier = Modifier
                  .clickable { showingDatePicker = true }
                  .testTag("bill.form.dueDate"),
              ) {
                DueDateChip(label = dueDate.dueDateLabel())
              }
            }
          }
          if (hasDueDate) {
            // The iOS `Form` footer: explanatory copy sits under the section's plate, not on it.
            Text(
              text = "A competência é o mês de referência da fatura. O vencimento pode cair em outro mês.",
              style = RentivoTypography.caption,
              color = RentivoColors.secondaryInk,
              modifier = Modifier.padding(horizontal = RentivoSpacing.medium),
            )
          }
        } }

        BillLineItemKind.entries.forEach { kind ->
          item(key = "lines-${kind.wire}") { FormSectionColumn(header = kind.sectionTitle) {
            val kindLines = lines.filter { it.kind == kind }
            // Only extras get an "add new line" affordance here: extras are the server's mechanism
            // for ad-hoc per-bill lines. Variable items are defined by the billing (cobrança)
            // itself, seeded above from `billing.items`; the live store's `variable_amounts` only
            // accepts the billing's own ULID-keyed variable items, so a client-minted UUID for a
            // brand-new variable line would silently be dropped on save. Previously seeded variable
            // lines still render and remain editable above.
            val addsLines = kind == BillLineItemKind.EXTRA
            if (kindLines.isNotEmpty() || addsLines) {
              RentivoListGroup {
                kindLines.forEachIndexed { position, line ->
                  if (position > 0) RentivoListDivider()
                  // `key` ties each row's composition — and with it the text field's cursor, focus
                  // and IME state — to the line's identity rather than to its position, so deleting
                  // a row above does not shift the one below into its slot. The callbacks resolve
                  // the index at event time for the same reason: an index captured at composition
                  // time goes stale the moment the list changes and would write to another line.
                  key(line.id.rawValue) {
                    BillLineRow(
                      line = line,
                      descriptionEditable = editRule.canEditDescription(kind),
                      amountEditable = editRule.canEditAmount(kind),
                      onDescriptionChange = { description ->
                        lines.updateLine(line.id) { it.copy(description = description) }
                      },
                      onCentavosChange = { centavos ->
                        lines.updateLine(line.id) { it.copy(centavos = centavos) }
                      },
                      // Fixed lines mirror the billing's own recurring items and aren't deletable
                      // here; only user-added variable/extra lines can be removed.
                      onDelete = if (!editRule.canDelete(kind)) {
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
                if (addsLines) {
                  if (kindLines.isNotEmpty()) RentivoListDivider()
                  AddLineRow(
                    label = "Adicionar ${kind.actionLabel}",
                    onClick = { lines.add(EditableBillLine.new(kind = kind)) },
                    modifier = Modifier.testTag("bill.form.addExtra"),
                  )
                }
              }
            }
          } }
        }

        item(key = "notes") { FormSectionColumn(header = "Observações") {
          RentivoListGroup {
            FormPlate {
              RentivoListField(
                value = notes,
                onValueChange = { notes = it },
                modifier = Modifier
                  .heightIn(min = NotesFieldMinHeight)
                  .testTag("bill.form.notes"),
                placeholder = "Mensagem opcional",
                singleLine = false,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
              )
            }
          }
        } }

        item(key = "total") { FormSectionColumn(header = "Total") {
          RentivoListGroup {
            FormPlate { MoneyText(money = total) }
          }
        } }

        if (issues.isNotEmpty()) {
          item(key = "issues") { FormSectionColumn(header = "Revise a fatura") {
            RentivoListGroup {
              issues.forEachIndexed { position, issue ->
                if (position > 0) RentivoListDivider()
                FormPlate {
                  IconLabel(
                    text = issue.message,
                    icon = Icons.Filled.Error,
                    style = RentivoTypography.body,
                    tint = RentivoColors.coral,
                  )
                }
              }
            }
          } }
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
  if (confirmingDiscard) {
    AlertDialog(
      onDismissRequest = { confirmingDiscard = false },
      title = { Text("Descartar as alterações?") },
      text = { Text("As alterações não salvas serão perdidas.") },
      confirmButton = {
        TextButton(onClick = { confirmingDiscard = false; onDismiss() }) {
          Text("Descartar", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingDiscard = false }) { Text("Continuar editando") }
      },
      containerColor = RentivoColors.surface,
    )
  }
}

/** The multi-line notes field's floor, i.e. the `lineLimit(3...6)` minimum the iOS form sets. */
private val NotesFieldMinHeight = 72.dp

/** The 44pt minimum iOS gives a row of a grouped `Form`, so a short row stays tappable. */
private val FormRowMinHeight = 44.dp

/** The removal glyph's own size; the tap target grows past it via the surrounding padding. */
private val LineDeleteGlyphSize = 20.dp

@Composable
private fun BillLineRow(
  line: EditableBillLine,
  descriptionEditable: Boolean,
  amountEditable: Boolean,
  onDescriptionChange: (String) -> Unit,
  onCentavosChange: (Long) -> Unit,
  onDelete: (() -> Unit)?,
) {
  Column(
    modifier = Modifier.padding(
      horizontal = RentivoSpacing.large,
      vertical = RentivoSpacing.small,
    ),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
  ) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      RentivoListField(
        value = line.description,
        onValueChange = onDescriptionChange,
        modifier = Modifier.weight(1f),
        placeholder = "Descrição",
        enabled = descriptionEditable,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
      )
      if (onDelete != null) {
        // A hairline minus glyph in secondary ink, not a filled red trash can: iOS reveals removal
        // behind a swipe, so an always-visible destructive control on every row read far louder
        // than the form it sits in.
        Icon(
          imageVector = Icons.Outlined.RemoveCircleOutline,
          contentDescription = "Remover ${line.description}",
          tint = RentivoColors.secondaryInk,
          modifier = Modifier
            .clip(CircleShape)
            .clickable(onClick = onDelete)
            .padding(RentivoSpacing.tiny)
            .size(LineDeleteGlyphSize),
        )
      }
    }
    CurrencyRowField(
      centavos = line.centavos,
      onCentavosChange = onCentavosChange,
      enabled = amountEditable,
    )
  }
}

/**
 * The "add another line" affordance: a full-width row led by a filled emerald plus-circle, i.e.
 * SwiftUI's `Label(_, systemImage: "plus.circle.fill")` sitting as the last row of a form section.
 */
@Composable
private fun AddLineRow(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .heightIn(min = FormRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = Icons.Filled.AddCircle,
      contentDescription = null,
      tint = RentivoColors.emerald,
    )
    Text(text = label, style = RentivoTypography.body, color = RentivoColors.emerald)
  }
}

/** The stepper's recessed capsule, matching the segmented control's groove radius. */
private val StepperShape = RoundedCornerShape(9.dp)
private val StepperDividerHeight = 22.dp
private val StepperButtonSize = 40.dp

/**
 * SwiftUI's `Stepper` control: the two buttons share one recessed capsule, split by a hairline,
 * rather than floating as a pair of loose icon buttons.
 */
@Composable
private fun YearStepper(
  canDecrease: Boolean,
  canIncrease: Boolean,
  onDecrease: () -> Unit,
  onIncrease: () -> Unit,
) {
  Row(
    modifier = Modifier
      .clip(StepperShape)
      .background(RentivoColors.segmentedTrack),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    StepperButton(
      icon = Icons.Filled.Remove,
      description = "Diminuir ano",
      enabled = canDecrease,
      onClick = onDecrease,
    )
    Box(
      modifier = Modifier
        .width(1.dp)
        .height(StepperDividerHeight)
        .background(RentivoColors.separator),
    )
    StepperButton(
      icon = Icons.Filled.Add,
      description = "Aumentar ano",
      enabled = canIncrease,
      onClick = onIncrease,
    )
  }
}

@Composable
private fun StepperButton(
  icon: ImageVector,
  description: String,
  enabled: Boolean,
  onClick: () -> Unit,
) {
  IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(StepperButtonSize)) {
    Icon(
      imageVector = icon,
      contentDescription = description,
      tint = if (enabled) RentivoColors.ink else RentivoColors.secondaryInk,
    )
  }
}

/** The tappable date value: a paper capsule, i.e. the plate iOS puts behind a compact `DatePicker`. */
@Composable
private fun DueDateChip(label: String) {
  Text(
    text = label,
    style = RentivoTypography.subheadlineEmphasized,
    color = RentivoColors.ink,
    modifier = Modifier
      .clip(CircleShape)
      .background(RentivoColors.paper)
      .padding(horizontal = RentivoSpacing.medium, vertical = 6.dp),
  )
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
  var pendingTransition by remember { mutableStateOf<BillTransition?>(null) }
  val mutationGate = remember { MutationGate() }
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

  suspend fun transition(currentStatus: BillStatus, status: BillStatus) {
    try {
      app.dependencies.bills.transitionBill(
        billingID = billing.id,
        billID = billId,
        currentStatus = currentStatus,
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

  Scaffold(
    modifier = Modifier.fillMaxSize(),
    containerColor = RentivoColors.paper,
    topBar = {
      RentivoInlineTopBar(
        title = "Fatura",
        onBack = onBack,
        actions = {
          if (loaded?.status == BillStatus.DRAFT && loaded.capabilities.canEdit) {
            TopBarChip {
              TextButton(
                onClick = { showingEdit = true },
                modifier = Modifier.testTag("bill.edit"),
              ) {
                Text(text = "Editar", color = RentivoColors.emerald)
              }
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
    ) { bill ->
      BillDetailContent(
        billing = currentBilling,
        bill = bill,
        modifier = Modifier.padding(padding),
        onTransition = { action ->
          if (action.requiresConfirmation) {
            pendingTransition = action
          } else {
            scope.launch { mutationGate.run { transition(bill.status, action.target) } }
          }
        },
        onOpenInvoice = { scope.launch { downloadInvoice() } },
        onOpenRecibo = { scope.launch { downloadRecibo() } },
        onRegenerate = { scope.launch { mutationGate.run { regenerate(bill) } } },
        onCompose = { showingCommunication = true },
        onDelete = { confirmingDelete = true },
        onMutation = { refreshAll() },
      )
    }
  }

  // Both are sheets, so they rise *over* the detail screen rather than replacing it — and each owns
  // its own back handling, which is why there is no screen-level `BackHandler` here.
  if (showingEdit && loaded != null) {
    BillFormSheet(
      billing = currentBilling,
      existing = loaded,
      onSaved = { refreshAll() },
      onDismiss = { showingEdit = false },
    )
  }

  if (showingCommunication && loaded != null) {
    CommunicationComposerSheet(
      billing = currentBilling,
      bill = loaded,
      onDismiss = { showingCommunication = false },
    )
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
            scope.launch { mutationGate.run { deleteBill() } }
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

  pendingTransition?.let { action ->
    AlertDialog(
      onDismissRequest = { pendingTransition = null },
      title = { Text(text = action.label) },
      text = { Text(text = "Confirme a alteração de status desta fatura.") },
      confirmButton = {
        TextButton(
          onClick = {
            pendingTransition = null
            val currentStatus = state.value?.status ?: return@TextButton
            scope.launch { mutationGate.run { transition(currentStatus, action.target) } }
          },
        ) {
          Text(
            text = action.label,
            color = if (action.style == "danger") RentivoColors.coral else RentivoColors.emerald,
          )
        }
      },
      dismissButton = {
        TextButton(onClick = { pendingTransition = null }) { Text(text = "Cancelar") }
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
  onTransition: (BillTransition) -> Unit,
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
            tint = RentivoColors.ink,
          )
        }
        bill.paidAt?.let { paidAt ->
          IconLabel(
            text = "Pago em ${paidAt.displayFormatted}",
            icon = Icons.Filled.Verified,
            style = RentivoTypography.subheadlineEmphasized,
            tint = RentivoColors.emerald,
          )
        }
      }
    }

    BillLineItemsSection(bill = bill)

    if (bill.capabilities.canTransition) {
      BillLifecycleSection(bill = bill, onTransition = onTransition)
    } else {
      IconLabel(
        text = "Ciclo disponível somente para quem pode gerenciar faturas.",
        icon = Icons.Filled.Visibility,
        style = RentivoTypography.caption,
      )
    }

    BillDocumentSection(
      bill = bill,
      onOpenInvoice = onOpenInvoice,
      onOpenRecibo = onOpenRecibo,
      onRegenerate = onRegenerate,
    )

    ReceiptManagerSection(
      billingID = billing.id,
      bill = bill,
      capabilities = bill.capabilities,
      onMutation = onMutation,
    )

    BillCommunicationHistorySection(bill = bill)

    if (bill.capabilities.canCompose) {
      RentivoButton(
        onClick = onCompose,
        enabled = bill.capabilities.canSendInvoice || bill.capabilities.canSendRecibo,
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
    }

    if (bill.capabilities.canDelete) {
      // Tinted, not destructive-red: iOS renders this as a plain `.bordered` button, and the
      // confirmation dialog behind it is what carries the destructive weight.
      RentivoTonalButton(
        onClick = onDelete,
        modifier = Modifier
          .fillMaxWidth()
          .testTag("bill.delete"),
      ) {
        Icon(imageVector = Icons.Filled.Delete, contentDescription = null)
        Text(text = "Excluir fatura", style = RentivoTypography.body)
      }
    }
  }
}

@Composable
private fun BillLineItemsSection(bill: Bill) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Composição", icon = Icons.AutoMirrored.Filled.FormatListBulleted)
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
          FormRowDivider()
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
private fun BillLifecycleSection(bill: Bill, onTransition: (BillTransition) -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Ciclo da fatura", icon = Icons.Filled.Autorenew)
    // Prefer the server-authoritative transitions for this specific bill (`available_transitions`)
    // over the local `BillStatus` state machine, when the API supplies them.
    if (bill.effectiveTransitionActions.isEmpty()) {
      IconLabel(
        text = "Esta fatura está em um estado final.",
        icon = Icons.Filled.CheckCircle,
        style = RentivoTypography.body,
      )
    } else {
      bill.effectiveTransitionActions.forEach { action ->
        // `.borderedProminent`, not the brutalist plate: the lifecycle actions are a stack of
        // equally weighted system buttons, and outlining each one turned the section into a wall.
        RentivoProminentButton(
          onClick = { onTransition(action) },
          modifier = Modifier
            .fillMaxWidth()
            .testTag("bill.transition.${action.target.wire}"),
        ) {
          Icon(imageVector = action.target.icon, contentDescription = null)
          Text(
            text = action.label,
            style = RentivoTypography.body,
          )
        }
      }
    }
    bill.statusUpdatedAt?.let { updatedAt ->
      Text(
        text = "Status atualizado em ${BILL_HISTORY_DATE_FORMAT.format(updatedAt)}.",
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
  }
}

@Composable
private fun BillCommunicationHistorySection(bill: Bill) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Comunicações", icon = Icons.Filled.Email)
    if (bill.communications.isEmpty()) {
      Text(
        text = "Nenhuma comunicação enviada.",
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    } else {
      RentivoCard {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
          bill.communications.forEachIndexed { index, item ->
            if (index > 0) RentivoListDivider()
            BillCommunicationHistoryRow(item = item)
          }
        }
      }
    }
  }
}

@Composable
private fun BillCommunicationHistoryRow(item: BillCommunication) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny)) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
      Text(
        text = item.createdAt?.let(BILL_HISTORY_DATE_FORMAT::format) ?: "Data indisponível",
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
      Spacer(modifier = Modifier.weight(1f))
      Text(
        text = item.deliveryLabel,
        style = RentivoTypography.caption,
        color = if (item.status == "failed") RentivoColors.coral else RentivoColors.secondaryInk,
      )
    }
    if (item.isRedacted) {
      Text(text = "Dados do destinatário protegidos", style = RentivoTypography.body)
    } else {
      Text(
        text = listOfNotNull(item.recipientName, item.recipientEmail).joinToString(" · "),
        style = RentivoTypography.body,
        color = RentivoColors.ink,
      )
      item.subject?.let { subject ->
        Text(
          text = subject,
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
        )
      }
    }
  }
}

@Composable
private fun BillDocumentSection(
  bill: Bill,
  onOpenInvoice: () -> Unit,
  onOpenRecibo: () -> Unit,
  onRegenerate: () -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Documento", icon = Icons.AutoMirrored.Filled.Article)
    when (bill.pdfRenderStatus) {
      PDFRenderStatus.PENDING -> Row(
        modifier = Modifier.testTag("bill.pdf.rendering"),
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        IconLabel(
          text = "Renderizando…",
          icon = Icons.Filled.Schedule,
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
        style = RentivoTypography.caption,
        tint = RentivoColors.coral,
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
      RentivoTonalButton(
        text = "Regenerar documento",
        onClick = onRegenerate,
        enabled = bill.capabilities.canRegenerate,
        modifier = Modifier
          .weight(1f)
          .testTag("bill.pdf.regenerate"),
      )
      if (bill.capabilities.canOpenRecibo) {
        RentivoTonalButton(
          text = "Abrir recibo",
          onClick = onOpenRecibo,
          enabled = !bill.isRenderingPDF,
          modifier = Modifier
            .weight(1f)
            .testTag("bill.recibo.open"),
        )
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
  capabilities: BillCapabilities,
  onMutation: suspend () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val context = LocalContext.current
  val resolver = context.contentResolver
  var downloadedFile by remember { mutableStateOf<DownloadedFile?>(null) }
  var pendingDeletion by remember { mutableStateOf<Receipt?>(null) }
  var openMenuFor by remember { mutableStateOf<ReceiptID?>(null) }
  var sourceMenuOpen by remember { mutableStateOf(false) }
  val mutationGate = remember(bill.id) { MutationGate() }
  val captures = remember(context) {
    ReceiptCaptureStore(File(context.cacheDir, ReceiptCaptureStore.DIRECTORY_NAME))
  }
  val hasCamera = remember(context) {
    context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
  }
  // The camera contract reports success or failure, not the URI it was handed, so the destination
  // has to survive from launch to callback — and the activity can be destroyed in between, since
  // the camera app is what the user is looking at. Saved rather than remembered, because the
  // result registry redelivers the capture after recreation and a remembered destination would be
  // null by then: the photo would be dropped and its file left behind.
  var pendingCapturePath by rememberSaveable { mutableStateOf<String?>(null) }

  suspend fun report(throwable: Throwable) {
    app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
  }

  /**
   * The one upload path every source funnels into. [cleanup] runs whatever the outcome, so a
   * temporary capture is deleted after a failed upload just as it is after a successful one.
   */
  fun uploadReceipt(cleanup: () -> Unit = {}, build: suspend () -> FileUpload) {
    scope.launch {
      if (mutationGate.isRunning) {
        cleanup()
        return@launch
      }
      mutationGate.run {
        try {
          app.dependencies.bills.addReceipt(
            billingID = billingID,
            billID = bill.id,
            upload = build(),
          )
          onMutation()
        } catch (cancellation: CancellationException) {
          throw cancellation
        } catch (throwable: Throwable) {
          report(throwable)
        } finally {
          cleanup()
        }
      }
    }
  }

  val documentPicker =
    rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
      if (uri == null) return@rememberLauncherForActivityResult
      uploadReceipt { prepareReceiptUpload(fileUploadFromUri(resolver = resolver, uri = uri)) }
    }

  // The system photo picker: it hands over one image without the app holding any storage
  // permission, which is why photos are a separate source from documents rather than a filter.
  val photoPicker =
    rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
      if (uri == null) return@rememberLauncherForActivityResult
      uploadReceipt { prepareReceiptUpload(fileUploadFromUri(resolver = resolver, uri = uri)) }
    }

  val cameraPicker =
    rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { captured ->
      val destination = pendingCapturePath?.let(::File)
        ?: return@rememberLauncherForActivityResult
      pendingCapturePath = null
      if (!captured) {
        ReceiptCaptureStore.remove(destination)
        return@rememberLauncherForActivityResult
      }
      uploadReceipt(cleanup = { ReceiptCaptureStore.remove(destination) }) {
        prepareReceiptUpload(fileUploadFromCapture(destination))
      }
    }

  // Creating the destination, granting it to the camera and resolving a camera app can all fail
  // (no camera on the device, a full cache), and none of it happens inside a coroutine.
  fun launchCamera() {
    val destination = runCatching { captures.makeDestination() }.getOrElse { throwable ->
      scope.launch { report(throwable) }
      return
    }
    pendingCapturePath = destination.absolutePath
    try {
      cameraPicker.launch(
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", destination),
      )
    } catch (throwable: Throwable) {
      pendingCapturePath = null
      ReceiptCaptureStore.remove(destination)
      scope.launch { report(throwable) }
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
              Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
              ) {
                IconLabel(
                  text = receipt.name,
                  icon = Icons.AutoMirrored.Filled.InsertDriveFile,
                  style = RentivoTypography.subheadline,
                )
                if (receipt.byteCount > 0) {
                  Text(
                    text = Formatter.formatShortFileSize(context, receipt.byteCount.toLong()),
                    style = RentivoTypography.caption,
                    color = RentivoColors.secondaryInk,
                  )
                }
              }
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
                  if (capabilities.canDeleteReceipts) {
                    DropdownMenuItem(
                      text = { Text(text = "Excluir", color = RentivoColors.coral) },
                      onClick = {
                        openMenuFor = null
                        pendingDeletion = receipt
                      },
                      enabled = !mutationGate.isRunning,
                    )
                  }
                }
              }
            }
          }
          // Drag-to-reorder would need these rows hosted in a reorderable list, but this section
          // renders inside a `RentivoCard` on a scrolling column. Kept as an explicit action
          // instead of restructuring the whole detail screen's layout.
          if (bill.receipts.size > 1 && capabilities.canReorderReceipts) {
            RentivoTonalButton(
              text = "Inverter ordem",
              onClick = {
                scope.launch {
                  mutationGate.run {
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
                }
              },
              enabled = !mutationGate.isRunning,
              modifier = Modifier.testTag("bill.receipts.reverse"),
            )
          }
        }
      }
    }
    if (capabilities.canUploadReceipts) {
      // The three sources hang off the button that opens them, like the per-receipt menu above:
      // tapping outside or pressing back dismisses without choosing one.
      Box {
        RentivoTonalButton(
          onClick = { sourceMenuOpen = true },
          enabled = !mutationGate.isRunning,
          modifier = Modifier.testTag("bill.receipts.add"),
        ) {
          Icon(imageVector = Icons.Filled.Add, contentDescription = null)
          Text(text = "Adicionar comprovante", style = RentivoTypography.body)
        }
        DropdownMenu(
          expanded = sourceMenuOpen,
          onDismissRequest = { sourceMenuOpen = false },
        ) {
          ReceiptSourceMenuItem(
            text = "Arquivos",
            icon = Icons.Filled.Folder,
            testTag = "bill.receipts.source.files",
            onClick = {
              sourceMenuOpen = false
              documentPicker.launch(arrayOf("application/pdf", "image/*"))
            },
          )
          // Camera hardware is optional (see the manifest's `uses-feature`), so a device without
          // any is offered only the two sources that can work — as on iOS, where the source is
          // hidden when the picker reports it unavailable.
          if (hasCamera) {
            ReceiptSourceMenuItem(
              text = "Câmera",
              icon = Icons.Filled.PhotoCamera,
              testTag = "bill.receipts.source.camera",
              onClick = {
                sourceMenuOpen = false
                launchCamera()
              },
            )
          }
          ReceiptSourceMenuItem(
            text = "Fotos",
            icon = Icons.Filled.PhotoLibrary,
            testTag = "bill.receipts.source.photos",
            onClick = {
              sourceMenuOpen = false
              photoPicker.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
              )
            },
          )
        }
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
              mutationGate.run {
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

/** One entry of the "Adicionar comprovante" source menu. */
@Composable
private fun ReceiptSourceMenuItem(
  text: String,
  icon: ImageVector,
  testTag: String,
  onClick: () -> Unit,
) {
  DropdownMenuItem(
    text = { Text(text = text) },
    onClick = onClick,
    leadingIcon = {
      Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.ink)
    },
    modifier = Modifier.testTag(testTag),
  )
}

// MARK: - Shared pieces

/**
 * A titled block of the form: the plain secondary header the shared [SectionHeader] draws, above
 * the section's plate. Deliberately without a [SectionTitle] glyph — an iOS `Form` section header is
 * unadorned text, and a 28dp icon per section turned the form into a list of headlines.
 *
 * The header is indented off the page margin, like the one over a `Form` section on iOS and like
 * the sibling "Nova cobrança" form's.
 */
@Composable
private fun FormSectionColumn(header: String, content: @Composable () -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Box(modifier = Modifier.padding(horizontal = RentivoSpacing.medium)) { SectionHeader(header) }
    content()
  }
}

/**
 * A labelled form row: the label on the leading edge, the control on the trailing edge.
 *
 * The row insets itself rather than leaning on a container's padding, because it sits directly on a
 * [RentivoListGroup] plate — [RentivoSpacing.large] is what lines its text up with the separators.
 */
@Composable
private fun FormRow(
  label: String,
  modifier: Modifier = Modifier,
  content: @Composable () -> Unit,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .heightIn(min = FormRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(text = label, style = RentivoTypography.body, color = RentivoColors.ink)
    Row(verticalAlignment = Alignment.CenterVertically) { content() }
  }
}

/** A plate row that is a single unlabelled control: the row inset, and nothing else. */
@Composable
private fun FormPlate(content: @Composable () -> Unit) {
  Box(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = FormRowMinHeight)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium),
    contentAlignment = Alignment.CenterStart,
  ) {
    content()
  }
}

/** The month name alone, capitalized: "agosto de 2026" -> "Agosto". */
private fun monthName(year: Int, month: Int): String =
  ReferenceMonth(year = year, month = month).label.substringBefore(" de ").capitalizedPTBR()

/**
 * The label a compact pt-BR `DatePicker` shows, e.g. "10 de set. de 2026".
 *
 * The abbreviation is the month name's first three letters, which is exactly how pt-BR shortens all
 * twelve; deriving it from [ReferenceMonth.label] keeps the names in one place rather than seeding a
 * second table here, and keeps them independent of the device locale's CLDR data.
 */
private fun LocalDate.dueDateLabel(): String {
  val abbreviation = ReferenceMonth(year = year, month = monthValue)
    .label
    .substringBefore(" de ")
    .take(3)
  return "$dayOfMonth de $abbreviation. de $year"
}

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
    BillStatus.PAID -> Icons.Filled.Verified
    BillStatus.CANCELLED -> Icons.Filled.Cancel
    BillStatus.DELAYED_PAYMENT -> Icons.Filled.Schedule
  }
