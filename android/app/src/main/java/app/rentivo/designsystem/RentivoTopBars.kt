package app.rentivo.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll

/**
 * The two navigation-bar treatments the iOS app uses, so feature screens stop hand-rolling
 * `TopAppBar`s that each drift a little differently.
 *
 * [RentivoLargeTopBar] is `navigationTitle` + `.large`: a tab root shows its title at display size
 * on its own line, collapsing to the 22sp title as content scrolls under it. [RentivoInlineTopBar]
 * is `.navigationBarTitleDisplayMode(.inline)`: a pushed screen centers a compact title between the
 * back chevron and the trailing action, each sitting in a circular surface chip like the iOS 26
 * toolbar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RentivoLargeTopBar(
  title: String,
  modifier: Modifier = Modifier,
  navigationIcon: (@Composable () -> Unit)? = null,
  scrollBehavior: TopAppBarScrollBehavior? = null,
  actions: @Composable RowScope.() -> Unit = {},
) {
  LargeTopAppBar(
    title = { Text(text = title, style = RentivoTypography.display, color = RentivoColors.ink) },
    modifier = modifier,
    navigationIcon = {
      if (navigationIcon != null) {
        // Material sets the collapsed title flush against the navigation slot, which leaves the
        // 22sp title touching the back chip. iOS keeps a gap between the two, so the slot carries
        // its own trailing space — and only when there is a chip to separate the title from.
        Row(verticalAlignment = Alignment.CenterVertically) {
          navigationIcon()
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
        }
      }
    },
    actions = actions,
    scrollBehavior = scrollBehavior,
    colors = TopAppBarDefaults.largeTopAppBarColors(
      containerColor = RentivoColors.paper,
      scrolledContainerColor = RentivoColors.paper,
      titleContentColor = RentivoColors.ink,
      navigationIconContentColor = RentivoColors.ink,
      actionIconContentColor = RentivoColors.emerald,
    ),
  )
}

/**
 * A screen whose chrome is a [RentivoLargeTopBar]: the paper page, the large PT-BR title, and the
 * collapse-on-scroll behavior that goes with it.
 *
 * Both halves of that behavior have to be wired together, which is why they live here rather than
 * at each screen:
 *
 * - The bar collapses only if it is given a `scrollBehavior` *and* the scaffold forwards nested
 *   scroll into it. Screens that wired up neither kept a full-height title while their content
 *   scrolled underneath.
 * - `LargeTopAppBar` insets itself below the status bar, and so does the tab shell's own
 *   `Scaffold` around every tab. Consuming the inset here — once, for every screen — is what stops
 *   the two from reserving the same strip twice and floating the title down the page.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RentivoLargeTopBarScaffold(
  title: String,
  modifier: Modifier = Modifier,
  navigationIcon: (@Composable () -> Unit)? = null,
  actions: @Composable RowScope.() -> Unit = {},
  content: @Composable (PaddingValues) -> Unit,
) {
  val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

  Box(modifier = Modifier.consumeWindowInsets(WindowInsets.statusBars)) {
    Scaffold(
      modifier = modifier
        .fillMaxSize()
        .nestedScroll(scrollBehavior.nestedScrollConnection),
      containerColor = RentivoColors.paper,
      topBar = {
        RentivoLargeTopBar(
          title = title,
          navigationIcon = navigationIcon,
          scrollBehavior = scrollBehavior,
          actions = actions,
        )
      },
      content = content,
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RentivoInlineTopBar(
  title: String,
  modifier: Modifier = Modifier,
  onBack: (() -> Unit)? = null,
  actions: @Composable RowScope.() -> Unit = {},
) {
  CenterAlignedTopAppBar(
    title = { Text(text = title, style = RentivoTypography.cardTitle, color = RentivoColors.ink) },
    modifier = modifier,
    navigationIcon = {
      if (onBack != null) {
        TopBarChip {
          IconButton(onClick = onBack) {
            Icon(
              imageVector = Icons.AutoMirrored.Filled.ArrowBack,
              contentDescription = "Voltar",
              tint = RentivoColors.ink,
            )
          }
        }
      }
    },
    actions = actions,
    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
      containerColor = RentivoColors.paper,
      titleContentColor = RentivoColors.ink,
      navigationIconContentColor = RentivoColors.ink,
      actionIconContentColor = RentivoColors.emerald,
    ),
  )
}

/**
 * The circular surface chip iOS 26 draws behind toolbar controls. Wrap an `IconButton` or a
 * `TextButton` placed in a top bar's `navigationIcon`/`actions` slot.
 */
@Composable
fun TopBarChip(content: @Composable () -> Unit) {
  Box(
    modifier = Modifier
      .clip(CircleShape)
      .background(RentivoColors.surface),
  ) {
    content()
  }
}
