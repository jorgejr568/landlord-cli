package app.rentivo.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip

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
  navigationIcon: @Composable () -> Unit = {},
  scrollBehavior: TopAppBarScrollBehavior? = null,
  actions: @Composable RowScope.() -> Unit = {},
) {
  LargeTopAppBar(
    title = { Text(text = title, style = RentivoTypography.display, color = RentivoColors.ink) },
    modifier = modifier,
    navigationIcon = navigationIcon,
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
