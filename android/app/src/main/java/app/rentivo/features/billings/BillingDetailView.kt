package app.rentivo.features.billings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.designsystem.FullScreenSheet
import app.rentivo.designsystem.IconLabel
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.OpaqueOverlay
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoInlineTopBar
import app.rentivo.designsystem.RentivoListDivider
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTonalButton
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.StatusBadge
import app.rentivo.designsystem.TopBarChip
import app.rentivo.designsystem.capitalizedPTBR
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.Bill
import app.rentivo.domain.BillID
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.DemoError
import app.rentivo.domain.Expense
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money
import app.rentivo.domain.ThemeTarget
import app.rentivo.features.bills.BillFormSheet
import app.rentivo.features.bills.BillingOperationsLinks
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/** Everything the detail screen renders, loaded as one unit. */
private data class BillingDetailData(
  val billing: Billing,
  val bills: List<Bill>,
  val expenses: List<Expense>,
)

/**
 * One billing in full. Port of `ios/Rentivo/Features/Billings/BillingDetailView.swift`.
 *
 * The iOS screen pushes its sub-screens through `NavigationLink`s; here the owning tab holds the
 * back stack, so each destination is requested through an `onOpen…` callback instead.
 */
@Composable
fun BillingDetailView(
  billingID: BillingID,
  onMutation: suspend () -> Unit,
  onOpenBill: (Billing, BillID) -> Unit,
  onOpenExpenses: (Billing) -> Unit,
  onOpenAttachments: (Billing) -> Unit,
  onOpenExport: (Billing) -> Unit,
  onOpenTheme: (ThemeTarget) -> Unit,
  onBack: () -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val state: MutableState<LoadState<BillingDetailData>> = remember { mutableStateOf(LoadState.Idle) }
  var showingEdit by remember { mutableStateOf(false) }
  var showingCreateBill by remember { mutableStateOf(false) }
  var confirmingDelete by remember { mutableStateOf(false) }

  suspend fun load() {
    // Unlike the list screens, the detail always blanks to Loading: it is a single record, and
    // showing a stale header while its bills and expenses are re-read would be a lie.
    state.value = LoadState.Loading
    state.value = try {
      LoadState.Loaded(
        BillingDetailData(
          billing = app.dependencies.billings.billing(id = billingID),
          bills = app.dependencies.bills.listBills(billingID = billingID),
          expenses = app.dependencies.expenses.listExpenses(billingID = billingID),
        )
      )
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      LoadState.Failed(DemoError.from(throwable))
    }
  }

  suspend fun deleteBilling() {
    try {
      app.dependencies.billings.deleteBilling(id = billingID)
      onMutation()
      app.showNotice("Cobrança excluída.")
      onBack()
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
    }
  }

  LaunchedEffect(app.dataRevision) { load() }

  Box(modifier = Modifier.rentivoPage()) {
    Scaffold(
      containerColor = RentivoColors.paper,
      topBar = {
        RentivoInlineTopBar(
          title = "Detalhes",
          onBack = onBack,
          actions = {
            if (state.value.value?.billing?.capabilities?.canEdit == true) {
              Box(modifier = Modifier.padding(end = RentivoSpacing.small)) {
                TopBarChip {
                  TextButton(
                    onClick = { showingEdit = true },
                    modifier = Modifier.testTag("billing.edit"),
                  ) {
                    Text(
                      text = "Editar",
                      style = RentivoTypography.body,
                      color = RentivoColors.emerald,
                    )
                  }
                }
              }
            }
          },
        )
      },
    ) { padding ->
      PageStateView(
        state = state.value,
        modifier = Modifier.padding(padding),
        retry = { scope.launch { load() } },
      ) { data ->
        BillingDetail(
          data = data,
          modifier = Modifier.padding(padding),
          onCreateBill = { showingCreateBill = true },
          onOpenBill = { billID -> onOpenBill(data.billing, billID) },
          onOpenExpenses = { onOpenExpenses(data.billing) },
          onOpenAttachments = { onOpenAttachments(data.billing) },
          onOpenExport = { onOpenExport(data.billing) },
          onOpenTheme = { onOpenTheme(ThemeTarget.Billing(id = billingID)) },
          onRequestDelete = { confirmingDelete = true },
        )
      }
    }

    val billing = state.value.value?.billing
    if (showingCreateBill && billing != null) {
      OpaqueOverlay {
        BackHandler { showingCreateBill = false }
        BillFormSheet(
          billing = billing,
          existing = null,
          onSaved = {
            load()
            onMutation()
          },
          onDismiss = { showingCreateBill = false },
        )
      }
    }
  }

  // The iOS screen presents the editor with `.sheet`, which covers the tab bar; the Compose
  // equivalent is a dialog-backed sheet, not an overlay composed inside the tab.
  val editing = state.value.value?.billing
  if (showingEdit && editing != null) {
    FullScreenSheet(onDismissRequest = { showingEdit = false }) {
      BillingFormView(
        existing = editing,
        onSaved = {
          load()
          onMutation()
        },
        onDismiss = { showingEdit = false },
      )
    }
  }

  if (confirmingDelete) {
    AlertDialog(
      onDismissRequest = { confirmingDelete = false },
      containerColor = RentivoColors.surface,
      title = { Text(text = "Excluir esta cobrança?") },
      text = { Text(text = "Faturas, despesas e arquivos desta cobrança também serão removidos.") },
      confirmButton = {
        TextButton(
          onClick = {
            confirmingDelete = false
            scope.launch { deleteBilling() }
          }
        ) {
          Text(text = "Excluir cobrança", color = RentivoColors.coral)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmingDelete = false }) {
          Text(text = "Cancelar", color = RentivoColors.ink)
        }
      },
    )
  }
}

@Composable
private fun BillingDetail(
  data: BillingDetailData,
  modifier: Modifier,
  onCreateBill: () -> Unit,
  onOpenBill: (BillID) -> Unit,
  onOpenExpenses: () -> Unit,
  onOpenAttachments: () -> Unit,
  onOpenExport: () -> Unit,
  onOpenTheme: () -> Unit,
  onRequestDelete: () -> Unit,
) {
  LazyColumn(
    modifier = modifier.fillMaxSize(),
    contentPadding = PaddingValues(RentivoSpacing.page),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
  ) {
    item { BillingHeaderCard(billing = data.billing) }
    item { LineItemsSection(items = data.billing.items) }
    item {
      BillsSection(
        data = data,
        onCreateBill = onCreateBill,
        onOpenBill = onOpenBill,
      )
    }
    item { FinancialSummarySection(data = data) }
    item {
      BillingOperationsLinks(
        billing = data.billing,
        onOpenExpenses = onOpenExpenses,
        onOpenAttachments = onOpenAttachments,
        onOpenExport = onOpenExport,
      )
    }
    item { RecipientsSection(billing = data.billing) }

    if (data.billing.capabilities.canReadTheme) {
      item {
        RentivoButton(
          onClick = onOpenTheme,
          color = RentivoColors.blue,
          modifier = Modifier.testTag("billing.theme"),
        ) {
          Icon(
            imageVector = Icons.Filled.Palette,
            contentDescription = null,
            tint = Color.White,
          )
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
          Text(
            text = "Aparência dos documentos",
            style = RentivoTypography.cardTitle,
            color = Color.White,
          )
        }
      }
    }

    item {
      if (data.billing.capabilities.canDelete) {
        // iOS renders `Button(role: .destructive).buttonStyle(.bordered)` as the tinted capsule,
        // not as a red outline — the destructive role only reaches the confirmation dialog.
        RentivoTonalButton(
          onClick = onRequestDelete,
          modifier = Modifier.fillMaxWidth(),
        ) {
          Icon(imageVector = Icons.Filled.Delete, contentDescription = null)
          Text(text = "Excluir cobrança", style = RentivoTypography.body)
        }
      } else {
        IconLabel(
          text = "Seu perfil pode consultar, mas não alterar esta cobrança.",
          icon = Icons.Filled.Visibility,
          style = RentivoTypography.metadata,
        )
      }
    }
  }
}

@Composable
private fun BillingHeaderCard(billing: Billing) {
  RentivoCard {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      Text(text = billing.name, style = RentivoTypography.title, color = RentivoColors.ink)
      Text(
        text = billing.description,
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
      IconLabel(
        text = billing.owner.name,
        icon = Icons.Filled.AccountBox,
        style = RentivoTypography.subheadlineEmphasized,
      )
      Row(verticalAlignment = Alignment.CenterVertically) {
        IconLabel(
          text = if (billing.pixOverride?.isComplete == true) "PIX próprio" else "PIX herdado",
          icon = Icons.Filled.QrCode2,
          style = RentivoTypography.metadata,
          modifier = Modifier.weight(1f),
        )
        MoneyText(money = billing.fixedSubtotal)
      }
    }
  }
}

@Composable
private fun LineItemsSection(items: List<BillingItem>) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    // `list.bullet.rectangle`: a bulleted list inside a box, which `ListAlt` matches and the
    // plain `FormatListBulleted` glyph does not.
    SectionTitle(title = "Itens recorrentes", icon = Icons.AutoMirrored.Filled.ListAlt)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        items.forEachIndexed { index, item ->
          Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
              modifier = Modifier.weight(1f),
              verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
            ) {
              Text(
                text = item.description,
                style = RentivoTypography.subheadlineEmphasized,
                color = RentivoColors.ink,
              )
              Text(
                text = item.type.label,
                style = RentivoTypography.caption,
                color = RentivoColors.secondaryInk,
              )
            }
            MoneyText(money = item.amount)
          }
          if (index != items.lastIndex) RentivoListDivider(indent = 0.dp)
        }
      }
    }
  }
}

@Composable
private fun BillsSection(
  data: BillingDetailData,
  onCreateBill: () -> Unit,
  onOpenBill: (BillID) -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      SectionTitle(
        title = "Faturas",
        icon = Icons.Filled.Description,
        modifier = Modifier.weight(1f),
      )
      if (data.billing.capabilities.canCreateBills) {
        IconButton(onClick = onCreateBill, modifier = Modifier.testTag("bill.create")) {
          Icon(
            imageVector = Icons.Filled.AddCircle,
            contentDescription = "Gerar fatura",
            tint = RentivoColors.emerald,
            modifier = Modifier.size(20.dp),
          )
        }
      }
    }
    if (data.bills.isEmpty()) {
      Text(
        text = "Nenhuma fatura foi gerada para esta cobrança.",
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
    } else {
      data.bills.forEach { bill ->
        BillRowCard(
          bill = bill,
          modifier = Modifier
            .clickable { onOpenBill(bill.id) }
            .testTag("bill.card.${bill.id.rawValue}"),
        )
      }
    }
  }
}

@Composable
private fun BillRowCard(bill: Bill, modifier: Modifier = Modifier) {
  RentivoCard(modifier = modifier) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Column(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      ) {
        Text(
          text = bill.referenceMonth.displayFormatted.capitalizedPTBR(),
          style = RentivoTypography.cardTitle,
          color = RentivoColors.ink,
        )
        StatusBadge(status = bill.status)
      }
      Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
      ) {
        MoneyText(money = bill.effectiveTotal)
        bill.dueDate?.let { dueDate ->
          Text(
            text = "Vence ${dueDate.displayFormatted}",
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
        }
      }
    }
  }
}

@Composable
private fun FinancialSummarySection(data: BillingDetailData) {
  val paid = data.bills.filter { it.status == BillStatus.PAID }
    .fold(Money.zero) { running, bill -> running + bill.effectiveTotal }
  val expenses = data.expenses.fold(Money.zero) { running, expense -> running + expense.amount }

  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Resumo financeiro", icon = Icons.Filled.BarChart)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        ValueRow(label = "Recebido", money = paid, color = RentivoColors.emerald)
        RentivoListDivider(indent = 0.dp)
        ValueRow(label = "Despesas", money = expenses, color = RentivoColors.coral)
        RentivoListDivider(indent = 0.dp)
        ValueRow(label = "Resultado", money = paid - expenses, color = RentivoColors.blue)
      }
    }
  }
}

@Composable
private fun ValueRow(label: String, money: Money, color: Color) {
  Row(verticalAlignment = Alignment.CenterVertically) {
    Text(
      text = label,
      style = RentivoTypography.subheadlineEmphasized,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    MoneyText(money = money, color = color)
  }
}

@Composable
private fun RecipientsSection(billing: Billing) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Destinatários", icon = Icons.Filled.Email)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
        billing.recipients.forEach { recipient ->
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
        billing.replyTo?.let { replyTo ->
          RentivoListDivider(indent = 0.dp)
          IconLabel(
            text = "Respostas para $replyTo",
            icon = Icons.AutoMirrored.Filled.Reply,
            style = RentivoTypography.caption,
          )
        }
      }
    }
  }
}
