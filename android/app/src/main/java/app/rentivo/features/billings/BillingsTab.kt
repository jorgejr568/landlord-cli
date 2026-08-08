package app.rentivo.features.billings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.TextStyle
import app.rentivo.designsystem.OpaqueOverlay
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.BillID
import app.rentivo.domain.Billing
import app.rentivo.domain.BillingID
import app.rentivo.domain.ThemeTarget
import app.rentivo.features.account.ThemeEditorScreen
import app.rentivo.features.bills.AttachmentListScreen
import app.rentivo.features.bills.BillDetailScreen
import app.rentivo.features.bills.ExpenseListScreen
import app.rentivo.features.bills.ExportScreen

/**
 * The screens the Cobranças tab can push over its list. Mirrors the iOS per-tab `NavigationStack`
 * destinations; because the stack is held in Compose state, whole domain objects travel with the
 * route instead of being re-fetched by id.
 */
private sealed interface BillingsRoute {
  data class Detail(val billingID: BillingID) : BillingsRoute

  data class BillDetail(val billing: Billing, val billID: BillID) : BillingsRoute

  data class Expenses(val billing: Billing) : BillingsRoute

  data class Attachments(val billing: Billing) : BillingsRoute

  data class Export(val billing: Billing) : BillingsRoute

  data class Theme(val target: ThemeTarget) : BillingsRoute
}

/**
 * The Cobranças tab and its navigation stack. Port of the `NavigationStack` wrapping
 * `BillingListView` in `ios/Rentivo/App/RootView.swift`.
 *
 * The list stays composed underneath the pushed screens so its search text, filter and scroll
 * position survive a round trip, exactly like a `NavigationStack` root does. Everything above the
 * root is rendered one screen at a time: popping back re-composes the screen underneath, which
 * re-runs its `load()` — the Compose analog of the iOS `onMutation` closures reloading their
 * parent.
 */
@Composable
fun BillingsTab() {
  val stack = remember { mutableStateListOf<BillingsRoute>() }
  // Bumped whenever something below the list mutates data, so the root reloads on the way back.
  var listReloadToken by remember { mutableIntStateOf(0) }

  // Guarded, and shared with the screens' own back affordances: two back events can arrive before
  // the recomposition that disables this handler, and popping an already-empty stack would throw.
  val pop: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

  BackHandler(enabled = stack.isNotEmpty(), onBack = pop)

  Box(modifier = Modifier.rentivoPage()) {
    BillingListView(
      reloadToken = listReloadToken,
      onOpenBilling = { billingID -> stack.add(BillingsRoute.Detail(billingID = billingID)) },
    )

    when (val route = stack.lastOrNull()) {
      null -> Unit

      is BillingsRoute.Detail -> OpaqueOverlay {
        BillingDetailView(
          billingID = route.billingID,
          onMutation = { listReloadToken += 1 },
          onOpenBill = { billing, billID ->
            stack.add(BillingsRoute.BillDetail(billing = billing, billID = billID))
          },
          onOpenExpenses = { billing -> stack.add(BillingsRoute.Expenses(billing = billing)) },
          onOpenAttachments = { billing ->
            stack.add(BillingsRoute.Attachments(billing = billing))
          },
          onOpenExport = { billing -> stack.add(BillingsRoute.Export(billing = billing)) },
          onOpenTheme = { target -> stack.add(BillingsRoute.Theme(target = target)) },
          onBack = pop,
        )
      }

      is BillingsRoute.BillDetail -> OpaqueOverlay {
        BillDetailScreen(
          billing = route.billing,
          billId = route.billID,
          onMutation = { listReloadToken += 1 },
          onBack = pop,
        )
      }

      is BillingsRoute.Expenses -> OpaqueOverlay {
        ExpenseListScreen(billing = route.billing, onBack = pop)
      }

      is BillingsRoute.Attachments -> OpaqueOverlay {
        AttachmentListScreen(billing = route.billing, onBack = pop)
      }

      is BillingsRoute.Export -> OpaqueOverlay {
        ExportScreen(billing = route.billing, onBack = pop)
      }

      is BillingsRoute.Theme -> OpaqueOverlay {
        ThemeEditorScreen(target = route.target, onBack = pop)
      }
    }
  }
}

/** The paper-on-ink navigation bar every screen in this tab uses. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun rentivoTopAppBarColors(): TopAppBarColors = TopAppBarDefaults.topAppBarColors(
  containerColor = RentivoColors.paper,
  titleContentColor = RentivoColors.ink,
  navigationIconContentColor = RentivoColors.ink,
  actionIconContentColor = RentivoColors.ink,
)

/** The Compose stand-in for SwiftUI's `Label(_:systemImage:)`. */
@Composable
internal fun IconLabel(
  text: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  style: TextStyle = RentivoTypography.metadata,
  color: Color = RentivoColors.secondaryInk,
) {
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = color,
      modifier = Modifier.size(16.dp),
    )
    Text(text = text, style = style, color = color)
  }
}
