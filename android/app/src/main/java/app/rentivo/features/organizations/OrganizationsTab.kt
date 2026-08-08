package app.rentivo.features.organizations

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.ThemeTarget
import app.rentivo.features.account.ThemeEditorScreen

/** One entry of the Organizações tab's navigation stack, above the always-present list root. */
private sealed interface OrganizationRoute {
  data class Detail(val id: OrganizationID) : OrganizationRoute

  data class Theme(val target: ThemeTarget) : OrganizationRoute
}

/**
 * The Organizações tab. Mirrors the iOS `NavigationStack` wrapping `OrganizationListView`.
 *
 * The list root stays composed underneath every pushed route, so popping back restores it — and its
 * scroll position — exactly like `NavigationStack` does. Pushed routes render as opaque full-bleed
 * layers in push order, which keeps intermediate screens alive across a deeper push.
 */
@Composable
fun OrganizationsTab() {
  val stack = remember { mutableStateListOf<OrganizationRoute>() }
  // The Compose stand-in for the iOS `onMutation` closure passed down the stack: bumping it reloads
  // the list root while it stays composed underneath.
  var listRefreshKey by remember { mutableIntStateOf(0) }

  BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }

  Box(modifier = Modifier.rentivoPage()) {
    OrganizationListView(
      refreshKey = listRefreshKey,
      onOpenOrganization = { id -> stack.add(OrganizationRoute.Detail(id)) },
    )

    stack.forEachIndexed { index, route ->
      key(index, route) {
        OpaqueOverlay {
          val popToHere: () -> Unit = { if (stack.size > index) stack.removeAt(stack.lastIndex) }
          when (route) {
            is OrganizationRoute.Detail -> OrganizationDetailView(
              organizationId = route.id,
              onMutation = { listRefreshKey += 1 },
              onOpenTheme = { target -> stack.add(OrganizationRoute.Theme(target)) },
              onBack = popToHere,
            )

            is OrganizationRoute.Theme -> ThemeEditorScreen(
              target = route.target,
              onBack = popToHere,
            )
          }
        }
      }
    }
  }
}
