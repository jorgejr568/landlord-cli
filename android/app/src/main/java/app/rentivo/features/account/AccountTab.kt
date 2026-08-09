package app.rentivo.features.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import app.rentivo.domain.ThemeTarget
import app.rentivo.features.demo.DemoScenariosScreen

/** The screens the Conta tab can push, mirroring the iOS `NavigationLink` destinations. */
private sealed interface AccountRoute {
  data object ProfilePix : AccountRoute

  data object Security : AccountRoute

  data object APIKeys : AccountRoute

  data object Theme : AccountRoute

  data object DemoScenarios : AccountRoute
}

/**
 * The Conta tab and its navigation stack, the analog of the iOS per-tab `NavigationStack`.
 *
 * The stack is a plain list of routes rather than a `NavHost`: destinations take whole domain values
 * (here only `ThemeTarget.User`, elsewhere entire billings), which route arguments cannot carry.
 */
@Composable
fun AccountTab() {
  val stack = remember { mutableStateListOf<AccountRoute>() }
  val pop: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

  BackHandler(enabled = stack.isNotEmpty(), onBack = pop)

  Box(modifier = Modifier.fillMaxSize()) {
    when (stack.lastOrNull()) {
      null -> AccountView(
        onOpenProfilePix = { stack.add(AccountRoute.ProfilePix) },
        onOpenSecurity = { stack.add(AccountRoute.Security) },
        onOpenAPIKeys = { stack.add(AccountRoute.APIKeys) },
        onOpenTheme = { stack.add(AccountRoute.Theme) },
        onOpenDemoScenarios = { stack.add(AccountRoute.DemoScenarios) },
      )

      AccountRoute.ProfilePix -> ProfilePixView(onBack = pop)
      AccountRoute.Security -> SecurityView(onBack = pop)
      AccountRoute.APIKeys -> APIKeyListScreen(onBack = pop)
      AccountRoute.Theme -> ThemeEditorScreen(target = ThemeTarget.User, onBack = pop)
      AccountRoute.DemoScenarios -> DemoScenariosScreen(onBack = pop)
    }
  }
}
