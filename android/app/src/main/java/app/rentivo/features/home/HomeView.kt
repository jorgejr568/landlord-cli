package app.rentivo.features.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Percent
import androidx.compose.material.icons.filled.RunningWithErrors
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppTab
import app.rentivo.app.LocalAppModel
import app.rentivo.data.DashboardSummary
import app.rentivo.domain.ActivityKind
import app.rentivo.domain.Bill
import app.rentivo.domain.BillID
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money
import app.rentivo.domain.RecentActivity
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.IconLabel
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoLargeTopBar
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.SectionTitle
import app.rentivo.designsystem.StatusBadge
import app.rentivo.designsystem.capitalizedPTBR
import app.rentivo.designsystem.ptBRCount
import kotlinx.coroutines.launch

/** How many upcoming bills and activity entries the dashboard shows before it stops. */
private const val UpcomingBillsShown = 4
private const val ActivitiesShown = 5

/** The dashboard tile disc, and the symbol knocked out of it. */
private val SummaryIconSize = 28.dp
private val SummaryGlyphSize = 17.dp

/**
 * The dashboard screen. Port of the `HomeView` body in
 * `ios/Rentivo/Features/Home/HomeView.swift`; its load state is owned by [HomeTab].
 *
 * @param reload re-runs the dashboard load, for pull-to-refresh and the error state's retry.
 * @param onOpenBill pushes a bill's detail screen onto the tab's stack.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HomeView(
  state: LoadState<HomeData>,
  reload: suspend () -> Unit,
  onOpenBill: (Billing, BillID) -> Unit,
) {
  val scope = rememberCoroutineScope()
  var isRefreshing by remember { mutableStateOf(false) }
  // `.large` on iOS: "Início" reads at display size on its own line and shrinks onto the bar as the
  // dashboard scrolls, so a card never ends up half-hidden behind an opaque inline bar.
  val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(
    state = rememberTopAppBarState(),
  )

  // The tab shell's `Scaffold` already insets every tab below the status bar. Consuming that inset
  // here is what stops the top bar — which pads itself against the system bars by default — from
  // reserving the same strip a second time and floating the title down the screen.
  Box(modifier = Modifier.consumeWindowInsets(WindowInsets.statusBars)) {
    Scaffold(
      modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
      containerColor = RentivoColors.paper,
      topBar = {
        RentivoLargeTopBar(
          title = "Início",
          scrollBehavior = scrollBehavior,
          actions = {
            BrandMark(compact = true, modifier = Modifier.padding(end = RentivoSpacing.medium))
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
              reload()
            } finally {
              isRefreshing = false
            }
          }
        },
        modifier = Modifier
          .fillMaxSize()
          .padding(padding),
      ) {
        PageStateView(state = state, retry = { scope.launch { reload() } }) { data ->
          HomeContent(data = data, onOpenBill = onOpenBill)
        }
      }
    }
  }
}

@Composable
private fun HomeContent(
  data: HomeData,
  onOpenBill: (Billing, BillID) -> Unit,
) {
  LazyColumn(
    modifier = Modifier.fillMaxSize(),
    // The floating tab bar is a translucent capsule the content scrolls beneath, so the last card
    // needs more than page padding under it to clear the bar rather than sit half-behind it.
    contentPadding = PaddingValues(
      start = RentivoSpacing.page,
      top = RentivoSpacing.page,
      end = RentivoSpacing.page,
      bottom = RentivoSpacing.page + RentivoSpacing.section,
    ),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.section),
  ) {
    item { GreetingSection(overdue = data.summary.overdue) }
    item { SummaryGrid(summary = data.summary) }
    if (data.hasBillings) {
      if (data.overdueBills.isNotEmpty()) {
        item { OverdueSection(count = data.overdueBills.size) }
      }
      item { QuickActionsSection() }
      if (data.upcomingBills.isNotEmpty()) {
        item {
          BillsSection(
            title = "Próximas faturas",
            bills = data.upcomingBills.take(UpcomingBillsShown),
            billings = data.billings,
            onOpenBill = onOpenBill,
          )
        }
      }
    } else {
      item { NoBillingsSection() }
    }
    item { ActivitySection(activities = data.activities) }
  }
}

@Composable
private fun GreetingSection(overdue: Money) {
  val app = LocalAppModel.current
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
    Text(text = "Olá!", style = RentivoTypography.display, color = RentivoColors.ink)
    Text(
      text = if (app.usesLiveAPI) {
        "Seu portfólio está conectado ao Rentivo."
      } else {
        "Seu portfólio está pronto para a demonstração."
      },
      style = RentivoTypography.body,
      color = RentivoColors.secondaryInk,
    )
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(top = RentivoSpacing.small),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      IconLabel(
        text = "Saldo em atraso",
        // The closest Material glyph to the iOS `clock.badge.exclamationmark`: a clock face whose
        // hands are replaced by an exclamation mark. `MoreTime` and `AccessAlarm` are the other
        // candidates, but a plus sign and an alarm bell both say something the label does not.
        icon = Icons.Filled.RunningWithErrors,
        modifier = Modifier.weight(1f),
        style = RentivoTypography.metadata,
        tint = RentivoColors.ink,
      )
      MoneyText(money = overdue, color = RentivoColors.coral)
    }
  }
}

/**
 * The four dashboard tiles. The iOS `LazyVGrid` of two flexible columns is two rows of equally
 * weighted cards here — a nested `LazyVerticalGrid` cannot be measured inside a `LazyColumn`.
 */
@Composable
private fun SummaryGrid(summary: DashboardSummary) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    Row(horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      SummaryCard(
        title = "Recebido",
        value = summary.received,
        icon = Icons.Filled.ArrowDownward,
        color = RentivoColors.emerald,
        modifier = Modifier.weight(1f),
      )
      SummaryCard(
        title = "Despesas",
        value = summary.expenses,
        icon = Icons.Filled.ArrowUpward,
        color = RentivoColors.coral,
        modifier = Modifier.weight(1f),
      )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      SummaryCard(
        title = "Resultado",
        value = summary.netIncome,
        icon = Icons.AutoMirrored.Filled.TrendingUp,
        color = RentivoColors.blue,
        modifier = Modifier.weight(1f),
      )
      CollectionCard(
        percent = summary.collectionRatePercent,
        modifier = Modifier.weight(1f),
      )
    }
  }
}

@Composable
private fun SummaryCard(
  title: String,
  value: Money,
  icon: ImageVector,
  color: Color,
  modifier: Modifier = Modifier,
) {
  RentivoCard(modifier = modifier) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
      SummaryIcon(icon = icon, color = color)
      Text(text = title, style = RentivoTypography.metadata, color = RentivoColors.secondaryInk)
      MoneyText(
        money = value,
        color = RentivoColors.ink,
        // The iOS tile uses `.system(.subheadline, design: .monospaced, weight: .bold)` — smaller
        // than the default money style so four-figure amounts fit two to a row.
        style = RentivoTypography.subheadline.copy(
          fontFamily = FontFamily.Monospace,
          fontWeight = FontWeight.Bold,
        ),
        minimumScaleFactor = 0.7f,
        maxLines = 1,
        contentDescriptionOverride = "$title: ${value.formatted()}",
      )
    }
  }
}

@Composable
private fun CollectionCard(
  percent: Int,
  modifier: Modifier = Modifier,
) {
  RentivoCard(modifier = modifier) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
      SummaryIcon(icon = Icons.Filled.Percent, color = RentivoColors.lilac)
      Text(
        text = "Taxa de recebimento",
        style = RentivoTypography.metadata,
        color = RentivoColors.secondaryInk,
      )
      Text(text = "$percent%", style = RentivoTypography.money, color = RentivoColors.ink)
    }
  }
}

/**
 * The glyph on a dashboard tile: a solid colored disc with a white symbol knocked out of it.
 *
 * iOS draws these with the `.fill` variants of its SF Symbols (`arrow.down.circle.fill`), where the
 * circle *is* the fill and the arrow is negative space. Material ships the arrows and the ring as
 * separate strokes, so the disc is composed here rather than taken from an outlined `ArrowCircle*`,
 * which reads as a thin ring next to the iOS tile.
 */
@Composable
private fun SummaryIcon(icon: ImageVector, color: Color) {
  Box(
    modifier = Modifier
      .size(SummaryIconSize)
      .clip(CircleShape)
      .background(color),
    contentAlignment = Alignment.Center,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = Color.White,
      modifier = Modifier.size(SummaryGlyphSize),
    )
  }
}

@Composable
private fun OverdueSection(count: Int) {
  val app = LocalAppModel.current
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Atenção necessária", icon = Icons.Filled.Warning)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        Text(
          text = "Há ${
            ptBRCount(
              count = count,
              singular = "fatura em acompanhamento",
              plural = "faturas em acompanhamento",
            )
          }",
          style = RentivoTypography.cardTitle,
          color = RentivoColors.ink,
        )
        Text(
          text = "Abra Cobranças para registrar o pagamento ou cancelar a fatura.",
          style = RentivoTypography.subheadline,
          color = RentivoColors.secondaryInk,
        )
        RentivoButton(text = "Ver cobranças", onClick = { app.selectedTab = AppTab.BILLINGS })
      }
    }
  }
}

@Composable
private fun QuickActionsSection() {
  val app = LocalAppModel.current
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Ações rápidas", icon = Icons.Filled.Bolt)
    // This action only switches to the Billings tab — it does not open a create flow (that would
    // require the Billings tab to observe a cross-tab "present create sheet" signal, which lives
    // outside the files this screen owns). Naming it "Ver cobranças" keeps the label honest about
    // what actually happens.
    RentivoButton(onClick = { app.selectedTab = AppTab.BILLINGS }) {
      Icon(imageVector = Icons.AutoMirrored.Filled.ListAlt, contentDescription = null, tint = Color.White)
      Spacer(modifier = Modifier.width(RentivoSpacing.small))
      Text(text = "Ver cobranças", style = RentivoTypography.cardTitle, color = Color.White)
    }
  }
}

@Composable
private fun NoBillingsSection() {
  val app = LocalAppModel.current
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Comece por aqui", icon = Icons.Filled.AutoAwesome)
    RentivoCard {
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
        Text(
          text = "Nenhuma cobrança cadastrada ainda",
          style = RentivoTypography.cardTitle,
          color = RentivoColors.ink,
        )
        Text(
          text = "Crie sua primeira cobrança recorrente na aba Cobranças para começar a " +
            "acompanhar recebimentos, despesas e faturas por aqui.",
          style = RentivoTypography.subheadline,
          color = RentivoColors.secondaryInk,
        )
        RentivoButton(text = "Ver cobranças", onClick = { app.selectedTab = AppTab.BILLINGS })
      }
    }
  }
}

@Composable
private fun BillsSection(
  title: String,
  bills: List<Bill>,
  billings: Map<BillingID, Billing>,
  onOpenBill: (Billing, BillID) -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = title, icon = Icons.Filled.CalendarMonth)
    bills.forEach { bill ->
      val billing = billings[bill.billingID]
      RentivoCard(
        modifier = Modifier
          .testTag("home.bill.card.${bill.id.rawValue}")
          // A bill always arrives with the billing it was listed from; without one there is
          // nothing to open a detail screen against, so the card stays inert.
          .clickable(enabled = billing != null) { billing?.let { onOpenBill(it, bill.id) } },
      ) {
        Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
          Row(verticalAlignment = Alignment.Top) {
            Column(
              modifier = Modifier.weight(1f),
              verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
            ) {
              Text(
                text = billing?.name ?: "Cobrança",
                style = RentivoTypography.cardTitle,
                color = RentivoColors.ink,
              )
              Text(
                text = bill.referenceMonth.label.capitalizedPTBR(),
                style = RentivoTypography.subheadline,
                color = RentivoColors.secondaryInk,
              )
            }
            StatusBadge(status = bill.status)
          }
          Row(verticalAlignment = Alignment.CenterVertically) {
            val dueDate = bill.dueDate
            if (dueDate != null) {
              IconLabel(
                text = "Vence em ${dueDate.displayFormatted}",
                icon = Icons.Filled.CalendarMonth,
                style = RentivoTypography.caption,
                tint = RentivoColors.ink,
              )
            }
            Spacer(modifier = Modifier.weight(1f))
            MoneyText(money = bill.effectiveTotal)
          }
        }
      }
    }
  }
}

@Composable
private fun ActivitySection(activities: List<RecentActivity>) {
  val app = LocalAppModel.current
  Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
    SectionTitle(title = "Atividade recente", icon = Icons.Filled.History)
    if (activities.isEmpty()) {
      Text(
        text = if (app.usesLiveAPI) {
          "Nenhuma atividade recente."
        } else {
          "As mudanças feitas na demonstração aparecerão aqui."
        },
        style = RentivoTypography.body,
        color = RentivoColors.secondaryInk,
      )
    } else {
      activities.take(ActivitiesShown).forEach { activity ->
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = RentivoSpacing.tiny),
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
          verticalAlignment = Alignment.Top,
        ) {
          Icon(
            imageVector = activity.kind.icon,
            contentDescription = null,
            tint = RentivoColors.emerald,
            modifier = Modifier.width(24.dp),
          )
          Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
          ) {
            Text(
              text = activity.title,
              style = RentivoTypography.subheadlineEmphasized,
              color = RentivoColors.ink,
            )
            Text(
              text = activity.detail,
              style = RentivoTypography.caption,
              color = RentivoColors.secondaryInk,
            )
          }
        }
      }
    }
  }
}

/** The icon each activity kind renders with, mirroring the iOS SF Symbol per kind. */
private val ActivityKind.icon: ImageVector
  get() = when (this) {
    ActivityKind.BILLING -> Icons.Filled.Home
    ActivityKind.BILL -> Icons.Filled.Description
    ActivityKind.EXPENSE -> Icons.Filled.Build
    ActivityKind.ORGANIZATION -> Icons.Filled.Apartment
    ActivityKind.INVITATION -> Icons.Filled.Email
    ActivityKind.SECURITY -> Icons.Filled.Shield
    ActivityKind.API_KEY -> Icons.Filled.VpnKey
    ActivityKind.THEME -> Icons.Filled.Palette
  }
