package app.rentivo.app

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import app.rentivo.designsystem.NoticeBanner
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.features.account.AccountTab
import app.rentivo.features.auth.AuthenticationView
import app.rentivo.features.billings.BillingsTab
import app.rentivo.features.home.HomeTab
import app.rentivo.features.organizations.OrganizationsTab

/**
 * The app shell. Port of `ios/Rentivo/App/RootView.swift`.
 *
 * Picks the screen for the current session, restores a stored session on first composition, and
 * overlays the transient notice banner above everything.
 */
@Composable
fun RootView() {
  val app = LocalAppModel.current

  LaunchedEffect(Unit) { app.restoreSessionIfNeeded() }

  Box(modifier = Modifier.fillMaxSize().background(RentivoColors.paper)) {
    when (app.session) {
      AppModel.Session.Restoring -> RestoringSessionView()
      AppModel.Session.Anonymous -> AuthenticationView()
      is AppModel.Session.Authenticated -> AuthenticatedTabView()
    }
    NoticeOverlay(modifier = Modifier.align(Alignment.TopCenter))
  }
}

@Composable
private fun RestoringSessionView() {
  Column(
    modifier = Modifier.fillMaxSize(),
    verticalArrangement = Arrangement.spacedBy(
      space = RentivoSpacing.medium,
      alignment = Alignment.CenterVertically,
    ),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    CircularProgressIndicator(color = RentivoColors.emerald)
    Text(
      text = "Restaurando sessão…",
      style = RentivoTypography.subheadline,
      color = RentivoColors.secondaryInk,
    )
  }
}

@Composable
private fun NoticeOverlay(modifier: Modifier = Modifier) {
  val app = LocalAppModel.current
  val notice = app.notice
  // AnimatedVisibility needs content to slide back out with, but `notice` is already null by then;
  // retaining the last one keeps the exit animation from collapsing into an empty banner.
  var retained by remember { mutableStateOf(notice) }
  if (notice != null) retained = notice

  AnimatedVisibility(
    visible = notice != null,
    modifier = modifier,
    enter = slideInVertically { height -> -height } + fadeIn(),
    exit = slideOutVertically { height -> -height } + fadeOut(),
  ) {
    retained?.let { shown ->
      NoticeBanner(
        notice = shown,
        dismiss = { app.notice = null },
        modifier = Modifier.padding(
          horizontal = RentivoSpacing.page,
          vertical = RentivoSpacing.small,
        ),
      )
    }
  }
}

/**
 * The four-tab shell shown to an authenticated user, mirroring the iOS `TabView`. Each tab hosts one
 * feature composable, which owns its own navigation stack.
 */
@Composable
fun AuthenticatedTabView() {
  val app = LocalAppModel.current

  Scaffold(
    containerColor = RentivoColors.paper,
    bottomBar = {
      NavigationBar(containerColor = RentivoColors.surface) {
        TabItems.forEach { item ->
          NavigationBarItem(
            selected = app.selectedTab == item.tab,
            onClick = { app.selectedTab = item.tab },
            icon = { Icon(imageVector = item.icon, contentDescription = null) },
            label = { Text(text = item.title) },
            colors = NavigationBarItemDefaults.colors(
              selectedIconColor = RentivoColors.emerald,
              selectedTextColor = RentivoColors.emerald,
              indicatorColor = RentivoColors.emeraldLight,
              unselectedIconColor = RentivoColors.secondaryInk,
              unselectedTextColor = RentivoColors.secondaryInk,
            ),
          )
        }
      }
    },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
      when (app.selectedTab) {
        AppTab.HOME -> HomeTab()
        AppTab.BILLINGS -> BillingsTab()
        AppTab.ORGANIZATIONS -> OrganizationsTab()
        AppTab.ACCOUNT -> AccountTab()
      }
    }
  }
}

private data class TabItem(val tab: AppTab, val title: String, val icon: ImageVector)

private val TabItems = listOf(
  TabItem(tab = AppTab.HOME, title = "Início", icon = Icons.Filled.Home),
  TabItem(tab = AppTab.BILLINGS, title = "Cobranças", icon = Icons.Filled.Description),
  TabItem(tab = AppTab.ORGANIZATIONS, title = "Organizações", icon = Icons.Filled.Apartment),
  TabItem(tab = AppTab.ACCOUNT, title = "Conta", icon = Icons.Filled.AccountCircle),
)
