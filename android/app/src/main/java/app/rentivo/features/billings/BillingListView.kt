package app.rentivo.features.billings

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.data.AppDependencies
import app.rentivo.designsystem.MoneyText
import app.rentivo.designsystem.PageStateView
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.StatusBadge
import app.rentivo.designsystem.ptBRCount
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.Bill
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.DemoError
import app.rentivo.domain.LoadState
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/** The owner segments of the list filter. Port of the iOS `BillingOwnerFilter`. */
private enum class BillingOwnerFilter(val label: String) {
  ALL("Todas"),
  PERSONAL("Pessoais"),
  ORGANIZATION("Organizações"),
}

/** One billing plus the bills that belong to it, as the portfolio card renders them. */
private data class BillingPortfolioItem(
  val billing: Billing,
  val bills: List<Bill>,
)

/**
 * The Cobranças list. Port of `ios/Rentivo/Features/Billings/BillingListView.swift`.
 *
 * [reloadToken] stands in for the iOS `onMutation` closure the detail screen calls back into: the
 * tab bumps it after a mutation deeper in the stack, which re-runs [load] exactly like
 * `await load()` does on iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BillingListView(
  reloadToken: Int,
  onOpenBilling: (BillingID) -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val state: MutableState<LoadState<List<BillingPortfolioItem>>> =
    remember { mutableStateOf(LoadState.Idle) }
  var searchText by rememberSaveable { mutableStateOf("") }
  var ownerFilter by rememberSaveable { mutableStateOf(BillingOwnerFilter.ALL) }
  var showingCreate by rememberSaveable { mutableStateOf(false) }
  var refreshing by remember { mutableStateOf(false) }

  // The iOS screen gates the create affordance on the demo viewer switch alone, without the
  // `!usesLiveAPI` guard the other screens apply; the port keeps that behavior as-is.
  val canCreateBilling = !app.demoSettings.viewerMode

  suspend fun load() {
    val hadContent = state.value.value != null
    if (!hadContent) state.value = LoadState.Loading
    try {
      val items = loadPortfolio(app.dependencies)
      state.value = if (items.isEmpty()) LoadState.Empty else LoadState.Loaded(items)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      // Preserve already-loaded content across a failed refresh instead of tearing down the list;
      // only surface the full-page error state when there was nothing to fall back to.
      if (hadContent) {
        app.showNotice(DemoError.from(throwable).message, AppNotice.Kind.WARNING)
      } else {
        state.value = LoadState.Failed(DemoError.from(throwable))
      }
    }
  }

  LaunchedEffect(app.dataRevision, reloadToken) { load() }

  Box(modifier = Modifier.rentivoPage()) {
    Scaffold(
      containerColor = RentivoColors.paper,
      topBar = {
        TopAppBar(
          title = { Text(text = "Cobranças") },
          colors = rentivoTopAppBarColors(),
          actions = {
            if (canCreateBilling) {
              IconButton(
                onClick = { showingCreate = true },
                modifier = Modifier.testTag("billing.create"),
              ) {
                Icon(imageVector = Icons.Filled.Add, contentDescription = "Nova cobrança")
              }
            }
          },
        )
      },
    ) { padding ->
      Column(modifier = Modifier.padding(padding).fillMaxSize()) {
        SearchField(
          text = searchText,
          onTextChange = { searchText = it },
          modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = RentivoSpacing.page, vertical = RentivoSpacing.small),
        )
        PullToRefreshBox(
          isRefreshing = refreshing,
          onRefresh = {
            scope.launch {
              refreshing = true
              try {
                load()
              } finally {
                refreshing = false
              }
            }
          },
          modifier = Modifier.weight(1f),
        ) {
          PageStateView(
            state = state.value,
            emptyTitle = "Nenhuma cobrança ainda",
            emptyMessage = "Crie sua primeira cobrança para começar a gerar faturas.",
            emptyIcon = Icons.Filled.Description,
            emptyActionTitle = if (canCreateBilling) "Nova cobrança" else null,
            emptyAction = if (canCreateBilling) ({ showingCreate = true }) else null,
            retry = { scope.launch { load() } },
          ) { items ->
            Portfolio(
              items = items,
              searchText = searchText,
              ownerFilter = ownerFilter,
              onOwnerFilterChange = { ownerFilter = it },
              onOpenBilling = onOpenBilling,
            )
          }
        }
      }
    }

    if (showingCreate) {
      Box(modifier = Modifier.rentivoPage()) {
        BillingFormView(
          existing = null,
          onSaved = { load() },
          onDismiss = { showingCreate = false },
        )
      }
    }
  }
}

/** Loads every billing together with its bills, exactly like the iOS sequential `for` loop. */
private suspend fun loadPortfolio(dependencies: AppDependencies): List<BillingPortfolioItem> =
  dependencies.billings.listBillings().map { billing ->
    BillingPortfolioItem(
      billing = billing,
      bills = dependencies.bills.listBills(billingID = billing.id),
    )
  }

@Composable
private fun SearchField(
  text: String,
  onTextChange: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  OutlinedTextField(
    value = text,
    onValueChange = onTextChange,
    modifier = modifier,
    singleLine = true,
    placeholder = { Text(text = "Buscar por nome, responsável ou descrição") },
    leadingIcon = { Icon(imageVector = Icons.Filled.Search, contentDescription = null) },
    shape = RoundedCornerShape(14.dp),
    colors = OutlinedTextFieldDefaults.colors(
      focusedBorderColor = RentivoColors.ink,
      unfocusedBorderColor = RentivoColors.ink,
      focusedContainerColor = RentivoColors.surface,
      unfocusedContainerColor = RentivoColors.surface,
      focusedTextColor = RentivoColors.ink,
      unfocusedTextColor = RentivoColors.ink,
      focusedPlaceholderColor = RentivoColors.secondaryInk,
      unfocusedPlaceholderColor = RentivoColors.secondaryInk,
      focusedLeadingIconColor = RentivoColors.secondaryInk,
      unfocusedLeadingIconColor = RentivoColors.secondaryInk,
    ),
  )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Portfolio(
  items: List<BillingPortfolioItem>,
  searchText: String,
  ownerFilter: BillingOwnerFilter,
  onOwnerFilterChange: (BillingOwnerFilter) -> Unit,
  onOpenBilling: (BillingID) -> Unit,
) {
  val filtered = filteredItems(items = items, searchText = searchText, ownerFilter = ownerFilter)

  LazyColumn(
    modifier = Modifier.fillMaxSize(),
    contentPadding = PaddingValues(RentivoSpacing.page),
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large),
  ) {
    item {
      SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        BillingOwnerFilter.entries.forEachIndexed { index, filter ->
          SegmentedButton(
            selected = ownerFilter == filter,
            onClick = { onOwnerFilterChange(filter) },
            shape = SegmentedButtonDefaults.itemShape(
              index = index,
              count = BillingOwnerFilter.entries.size,
            ),
          ) {
            Text(text = filter.label)
          }
        }
      }
    }

    if (filtered.isEmpty()) {
      item { SearchUnavailableView(searchText = searchText) }
    } else {
      items(items = filtered, key = { it.billing.id.rawValue }) { item ->
        BillingPortfolioCard(
          item = item,
          modifier = Modifier
            .clickable { onOpenBilling(item.billing.id) }
            .testTag("billing.card.${item.billing.id.rawValue}"),
        )
      }
    }
  }
}

/** Mirrors the iOS `ContentUnavailableView.search(text:)` the filtered-to-zero list falls back to. */
@Composable
private fun SearchUnavailableView(searchText: String) {
  val query = searchText.trim()
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .padding(top = RentivoSpacing.section),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Icon(
      imageVector = Icons.Filled.Search,
      contentDescription = null,
      tint = RentivoColors.secondaryInk,
      modifier = Modifier.size(44.dp),
    )
    Spacer(modifier = Modifier.height(RentivoSpacing.medium))
    Text(
      text = if (query.isEmpty()) "Nenhum resultado" else "Nenhum resultado para “$query”",
      style = RentivoTypography.title,
      color = RentivoColors.ink,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(RentivoSpacing.small))
    Text(
      text = "Verifique a ortografia ou tente uma nova busca.",
      style = RentivoTypography.subheadline,
      color = RentivoColors.secondaryInk,
      textAlign = TextAlign.Center,
    )
  }
}

private fun filteredItems(
  items: List<BillingPortfolioItem>,
  searchText: String,
  ownerFilter: BillingOwnerFilter,
): List<BillingPortfolioItem> = items.filter { item ->
  val matchesOwner = when (ownerFilter) {
    BillingOwnerFilter.ALL -> true
    BillingOwnerFilter.PERSONAL -> !item.billing.owner.isOrganization
    BillingOwnerFilter.ORGANIZATION -> item.billing.owner.isOrganization
  }
  val query = searchText.trim()
  val matchesSearch = query.isEmpty() ||
    item.billing.name.contains(query, ignoreCase = true) ||
    item.billing.description.contains(query, ignoreCase = true) ||
    item.billing.owner.name.contains(query, ignoreCase = true)
  matchesOwner && matchesSearch
}

@Composable
private fun BillingPortfolioCard(
  item: BillingPortfolioItem,
  modifier: Modifier = Modifier,
) {
  val ownsPix = item.billing.pixOverride?.isComplete == true

  RentivoCard(modifier = modifier) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.medium)) {
      Row(verticalAlignment = Alignment.Top) {
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        ) {
          Text(
            text = item.billing.name,
            style = RentivoTypography.cardTitle,
            color = RentivoColors.ink,
          )
          IconLabel(
            text = item.billing.owner.name,
            icon = if (item.billing.owner.isOrganization) {
              Icons.Filled.Apartment
            } else {
              Icons.Filled.Person
            },
          )
        }
        Icon(
          imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
          contentDescription = null,
          tint = RentivoColors.secondaryInk,
        )
      }

      Text(
        text = item.billing.description,
        style = RentivoTypography.subheadline,
        color = RentivoColors.secondaryInk,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
      )

      Row(verticalAlignment = Alignment.CenterVertically) {
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        ) {
          Text(
            text = "Subtotal fixo",
            style = RentivoTypography.caption,
            color = RentivoColors.secondaryInk,
          )
          MoneyText(money = item.billing.fixedSubtotal)
        }
        Column(
          horizontalAlignment = Alignment.End,
          verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        ) {
          IconLabel(
            text = ptBRCount(item.bills.size, singular = "fatura", plural = "faturas"),
            icon = Icons.Filled.Description,
          )
          IconLabel(
            text = if (ownsPix) "PIX próprio" else "PIX herdado",
            icon = if (ownsPix) Icons.Filled.QrCode2 else Icons.AutoMirrored.Filled.CallSplit,
          )
        }
      }

      item.bills.firstOrNull()?.let { first -> StatusBadge(status = first.status) }
    }
  }
}
