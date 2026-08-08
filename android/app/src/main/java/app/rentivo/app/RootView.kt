package app.rentivo.app

import androidx.activity.OnBackPressedDispatcher
import androidx.activity.OnBackPressedDispatcherOwner
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
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
 * The floating tab bar: an inset, fully-rounded translucent capsule the content scrolls beneath,
 * mirroring the iOS 26 floating `TabView` bar. There is deliberately no Material indicator pill —
 * iOS marks the selected item with the emerald tint alone.
 */
@Composable
private fun FloatingTabBar(selected: AppTab, onSelect: (AppTab) -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .navigationBarsPadding()
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.medium)
      .clip(CircleShape)
      .background(RentivoColors.surface.copy(alpha = 0.94f))
      .padding(horizontal = RentivoSpacing.small, vertical = RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    TabItems.forEach { item ->
      val active = selected == item.tab
      val tint = if (active) RentivoColors.emerald else RentivoColors.secondaryInk
      Column(
        modifier = Modifier
          .weight(1f)
          .clip(CircleShape)
          .clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            onClick = { onSelect(item.tab) },
          )
          .padding(vertical = RentivoSpacing.tiny + 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
      ) {
        Icon(imageVector = item.icon, contentDescription = item.title, tint = tint)
        Text(text = item.title, style = RentivoTypography.metadata, color = tint)
      }
    }
  }
}

/**
 * The four-tab shell shown to an authenticated user, mirroring the iOS `TabView`. Each tab hosts one
 * feature composable, which owns its own navigation stack.
 *
 * Like the iOS `TabView`, a tab keeps everything it built — navigation stack, filters, scroll
 * position, loaded data — once the user has been there. Composing only the selected tab would
 * instead tear all of that down on every switch, because each tab's state lives in `remember`s
 * inside it.
 *
 * So every *visited* tab stays composed for as long as the session lasts, and [TabSlot] neutralizes
 * the three ways an off-screen tab would otherwise interfere with the visible one. Tabs are composed
 * lazily rather than all four up front, so an unvisited tab never runs its initial load — the
 * Compose analogue of SwiftUI only firing `onAppear` for tabs the user actually opens.
 */
@Composable
fun AuthenticatedTabView() {
  val app = LocalAppModel.current

  // Deliberately a plain set, not snapshot state: it is written and read within the same
  // composition pass, and observing it would only invalidate this composable a second time for a
  // change it has already applied. It lives exactly as long as the authenticated session, so
  // signing out drops every tab's state, as it should.
  val visited = remember { mutableSetOf<AppTab>() }
  visited.add(app.selectedTab)

  Scaffold(
    containerColor = RentivoColors.paper,
    bottomBar = { FloatingTabBar(selected = app.selectedTab, onSelect = { app.selectedTab = it }) },
  ) { padding ->
    Box(modifier = Modifier.fillMaxSize().padding(padding)) {
      // Iterating the fixed `entries` order rather than visit order keeps every tab at the same
      // slot-table position for the whole session, so newly visiting one never shifts another.
      AppTab.entries.forEach { tab ->
        key(tab) {
          if (tab in visited) {
            TabSlot(active = tab == app.selectedTab) {
              when (tab) {
                AppTab.HOME -> HomeTab()
                AppTab.BILLINGS -> BillingsTab()
                AppTab.ORGANIZATIONS -> OrganizationsTab()
                AppTab.ACCOUNT -> AccountTab()
              }
            }
          }
        }
      }
    }
  }
}

/**
 * Hosts one tab of [AuthenticatedTabView], keeping it composed whether or not it is on screen.
 *
 * A composed-but-inactive tab has to be invisible, untouchable and deaf to the back gesture. All
 * three are handled here rather than in the feature tabs, which stay unaware they can be
 * backgrounded at all:
 *
 * - **Invisible and untouchable.** The content is measured — which is what keeps its composition,
 *   and therefore all of its `remember`ed state, alive — but simply not placed. An unplaced subtree
 *   is skipped by both the draw pass and hit testing, so it costs nothing to keep around and cannot
 *   steal a touch from the tab on top of it.
 * - **Deaf to back.** Placement has no bearing on [androidx.activity.compose.BackHandler], which
 *   registers with whatever `OnBackPressedDispatcher` it finds in composition. Every background tab
 *   would therefore keep an enabled handler on the activity's dispatcher, and since the dispatcher
 *   invokes the *last* enabled callback registered, back would pop some other tab's navigation
 *   stack. Handing inactive tabs their own inert dispatcher means only the active tab's handlers are
 *   ever on the real one, so there is nothing to arbitrate.
 *
 * Swapping the provided dispatcher does not disturb the content: it is the same composition group
 * either way, so `remember`s survive, and the `DisposableEffect` inside each `BackHandler` simply
 * re-registers the callback against the dispatcher that is now in scope.
 */
@Composable
private fun TabSlot(active: Boolean, content: @Composable () -> Unit) {
  val hostOwner = LocalOnBackPressedDispatcherOwner.current
  val lifecycleOwner = LocalLifecycleOwner.current
  val inertOwner = remember(lifecycleOwner) {
    object : OnBackPressedDispatcherOwner {
      override val lifecycle: Lifecycle get() = lifecycleOwner.lifecycle
      override val onBackPressedDispatcher = OnBackPressedDispatcher()
    }
  }

  // `hostOwner` is only absent where there is no back dispatcher to compete over in the first place
  // (a preview, or a bare-View host), so falling back to the inert one keeps that a no-op.
  val backOwner = (if (active) hostOwner else null) ?: inertOwner

  Box(
    modifier = Modifier.fillMaxSize().layout { measurable, constraints ->
      val placeable = measurable.measure(constraints)
      layout(placeable.width, placeable.height) {
        if (active) placeable.place(x = 0, y = 0)
      }
    },
  ) {
    CompositionLocalProvider(LocalOnBackPressedDispatcherOwner provides backOwner) {
      content()
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
