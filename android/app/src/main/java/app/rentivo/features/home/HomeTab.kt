package app.rentivo.features.home

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import app.rentivo.app.AppModel
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.data.DashboardSummary
import app.rentivo.domain.Bill
import app.rentivo.domain.BillID
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.DateOnly
import app.rentivo.domain.DemoError
import app.rentivo.domain.LoadState
import app.rentivo.domain.RecentActivity
import app.rentivo.features.bills.BillDetailScreen
import kotlin.coroutines.cancellation.CancellationException

/** Everything the dashboard renders, loaded in one pass. Port of the Swift `HomeData`. */
internal data class HomeData(
  val summary: DashboardSummary,
  val overdueBills: List<Bill>,
  val upcomingBills: List<Bill>,
  /**
   * The billings the bills above belong to, keyed by id. iOS only needs the *names* here, but the
   * Android `BillDetailScreen` takes the whole `Billing`, so the loaded objects are kept instead of
   * being flattened to a name map.
   */
  val billings: Map<BillingID, Billing>,
  val activities: List<RecentActivity>,
  val hasBillings: Boolean,
)

/** The one screen this tab can push onto its stack. */
private sealed interface HomeRoute {
  data class BillDetail(val billing: Billing, val billID: BillID) : HomeRoute
}

/** Statuses that make a bill "upcoming" — everything that is neither settled nor cancelled. */
private val UpcomingStatuses = setOf(BillStatus.DRAFT, BillStatus.PUBLISHED, BillStatus.SENT)

/**
 * The Início tab: the dashboard plus its navigation stack. Port of `HomeView` in
 * `ios/Rentivo/Features/Home/HomeView.swift` and the `NavigationStack` that wraps it.
 *
 * The load state lives here rather than inside [HomeView] — one level higher than the iOS
 * `HomeView` keeps it — for two reasons. Pushing a route swaps the dashboard out of the composition
 * (there is no `NavigationStack` keeping the root alive underneath), so hoisting the state is what
 * makes returning from a bill show the dashboard as it was instead of a fresh spinner. And acting
 * on a bill from its detail screen must reload the dashboard behind it, which needs the same
 * `load()` the screen itself uses.
 */
@Composable
fun HomeTab() {
  val app = LocalAppModel.current
  var state: LoadState<HomeData> by remember { mutableStateOf(LoadState.Idle) }
  val backStack = remember { mutableStateListOf<HomeRoute>() }

  suspend fun load() {
    // Only blank the screen with a spinner when nothing has been shown yet (first launch or a
    // previously-failed load). Pull-to-refresh and every data-revision bump otherwise refresh the
    // dashboard in place, keeping the current cards on screen.
    when (state) {
      LoadState.Idle, is LoadState.Failed -> state = LoadState.Loading
      LoadState.Loading, LoadState.Empty, is LoadState.Loaded -> Unit
    }
    try {
      // The dashboard (summary cards, activity) is always meaningful, even with zero billings —
      // it is shown with zeroed cards plus an explainer section rather than replaced by a generic
      // empty state that has no create action on this screen.
      state = LoadState.Loaded(loadHomeData(app))
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      if (state.value != null) {
        app.showNotice(DemoError.from(throwable).message, kind = AppNotice.Kind.WARNING)
      } else {
        state = LoadState.Failed(DemoError.from(throwable))
      }
    }
  }

  LaunchedEffect(app.dataRevision) { load() }
  BackHandler(enabled = backStack.isNotEmpty()) { backStack.removeAt(backStack.lastIndex) }

  when (val route = backStack.lastOrNull()) {
    null -> HomeView(
      state = state,
      reload = { load() },
      onOpenBill = { billing, billID ->
        backStack.add(HomeRoute.BillDetail(billing = billing, billID = billID))
      },
    )

    is HomeRoute.BillDetail -> BillDetailScreen(
      billing = route.billing,
      billId = route.billID,
      // Publishing, sending or deleting a bill from its detail screen changes the summary cards
      // and can drop the bill out of "Próximas faturas", so the dashboard behind the push is
      // reloaded rather than left stale.
      onMutation = { load() },
      onBack = { backStack.removeAt(backStack.lastIndex) },
    )
  }
}

/**
 * Fetches the dashboard in one pass: the summary, every billing, the bills of each billing (the
 * API has no cross-billing bill listing, so this is intentionally N+1), and the activity feed.
 */
private suspend fun loadHomeData(app: AppModel): HomeData {
  val summary = app.dependencies.dashboard.dashboardSummary()
  val billings = app.dependencies.billings.listBillings()
  val bills = billings.flatMap { billing -> app.dependencies.bills.listBills(billingID = billing.id) }
  return HomeData(
    summary = summary,
    overdueBills = bills.filter { it.status == BillStatus.DELAYED_PAYMENT },
    upcomingBills = upcomingBills(bills),
    billings = billings.associateBy { it.id },
    activities = app.dependencies.activities.recentActivities,
    hasBillings = billings.isNotEmpty(),
  )
}

/**
 * The bills still awaiting payment, soonest first. A bill with no due date has nothing to be
 * "upcoming" against, so it sorts after every dated bill rather than ahead of them.
 */
internal fun upcomingBills(bills: List<Bill>): List<Bill> =
  bills.filter { UpcomingStatuses.contains(it.status) }
    .sortedWith(compareBy(nullsLast<DateOnly>()) { it.dueDate })
