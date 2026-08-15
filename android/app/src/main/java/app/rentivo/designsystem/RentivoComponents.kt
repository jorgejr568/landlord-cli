package app.rentivo.designsystem

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.rentivo.app.AppNotice
import app.rentivo.app.LocalAppModel
import app.rentivo.domain.BillStatus
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money

private val CardShape = RoundedCornerShape(18.dp)
private val ControlShape = RoundedCornerShape(14.dp)

private val CardShadowOffset = 4.dp
private val ControlShadowOffset = 3.dp

/** Every bordered surface in the system uses the same 2dp ink outline. */
private val BorderStroke = 2.dp

/** The inset-grouped list plate: same 18dp radius as the cards, but borderless and shadowless. */
private val ListGroupShape = RoundedCornerShape(18.dp)

/** The sheet's rounded shoulders — iOS uses ~12pt on presented sheets. */
private val SheetShape = RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)

/** SectionTitle glyphs track the 22sp title style the way SF Symbols track `.title2`. */
private val SectionTitleIconSize = 28.dp

/** `UISegmentedControl` geometry: recessed track, floating pill, 2dp groove padding. */
private val SegmentedTrackShape = RoundedCornerShape(9.dp)
private val SegmentedPillShape = RoundedCornerShape(7.dp)
private val SegmentedTrackPadding = 2.dp

/**
 * A full-bleed, opaque layer above the content underneath — the Compose stand-in for both a SwiftUI
 * `.sheet` and a `NavigationStack` push.
 *
 * The empty click listener is load-bearing: a `Box` that only paints a background does not consume
 * pointer events, so taps would otherwise reach the screen rendered underneath. `indication = null`
 * keeps the layer from flashing a ripple when that happens.
 */
@Composable
fun OpaqueOverlay(content: @Composable () -> Unit) {
  Box(
    modifier = Modifier
      .rentivoPage()
      .clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        onClick = {},
      ),
  ) {
    content()
  }
}

/**
 * The neo-brutalist drop shadow: a solid, un-blurred copy of the shape, painted [offset] down and
 * to the right of the element it sits behind.
 *
 * This is deliberately *not* Material elevation — elevation renders a soft, blurred, ambient
 * shadow, which is the opposite of the look. It draws outside the element's own bounds, so callers
 * must reserve `offset` worth of trailing/bottom padding *outside* this modifier, exactly like the
 * iOS components do with their `.padding(.trailing/.bottom)` after `.shadow(radius: 0)`.
 */
fun Modifier.rentivoHardShadow(
  offset: Dp,
  cornerRadius: Dp,
  color: Color = RentivoColors.ink,
): Modifier = drawBehind {
  if (offset <= 0.dp) return@drawBehind
  val delta = offset.toPx()
  drawRoundRect(
    color = color,
    topLeft = Offset(delta, delta),
    size = size,
    cornerRadius = CornerRadius(cornerRadius.toPx()),
  )
}

/**
 * The surface every screen composes its content out of: cream fill, 18dp rounded corners, a 2dp
 * ink border and a hard 4dp offset shadow.
 *
 * Set [flat] to drop the border and the shadow (and the padding reserved for it), leaving just the
 * rounded fill. That is the iOS "grouped content" treatment: a card nested inside another card, or
 * one sitting directly on a form background where a second outline would only add noise.
 */
@Composable
fun RentivoCard(
  modifier: Modifier = Modifier,
  contentPadding: PaddingValues = PaddingValues(RentivoSpacing.large),
  flat: Boolean = false,
  content: @Composable ColumnScope.() -> Unit,
) {
  val shadowOffset = if (flat) 0.dp else CardShadowOffset
  Column(
    modifier = modifier
      .fillMaxWidth()
      // Reserve the space the offset shadow paints into, mirroring the iOS trailing/bottom padding.
      .padding(end = shadowOffset, bottom = shadowOffset)
      .rentivoHardShadow(offset = shadowOffset, cornerRadius = 18.dp)
      .clip(CardShape)
      .background(RentivoColors.surface)
      .then(
        if (flat) {
          Modifier
        } else {
          Modifier.border(width = BorderStroke, color = RentivoColors.ink, shape = CardShape)
        },
      )
      .padding(contentPadding),
    content = content,
  )
}

/**
 * The iOS inset-grouped list container: a pure white plate with 18dp corners, no outline and no
 * shadow, holding rows separated by inset hairlines.
 *
 * This overload is the one to reach for — it takes the rows as a list and draws the separators
 * between them itself, so a caller can never end up with a stray leading or trailing divider. Rows
 * pad themselves; use [RentivoSpacing.large] horizontally to line up with the default separator
 * inset:
 *
 * ```
 * RentivoListGroup(
 *   rows = listOf(
 *     { SettingsRow("Nome", profile.name) },
 *     { SettingsRow("E-mail", profile.email) },
 *   ),
 * )
 * ```
 *
 * Build the list conditionally with `buildList { add { … }; if (isOwner) add { … } }` — the
 * separators follow whatever survives. Reach for the slot overload plus [RentivoListDivider] only
 * when the rows cannot be expressed as a list at all.
 */
@Composable
fun RentivoListGroup(
  rows: List<@Composable () -> Unit>,
  modifier: Modifier = Modifier,
  dividerIndent: Dp = RentivoSpacing.large,
) {
  RentivoListGroup(modifier = modifier) {
    rows.forEachIndexed { index, row ->
      if (index > 0) RentivoListDivider(indent = dividerIndent)
      row()
    }
  }
}

/**
 * Slot form of [RentivoListGroup]: the same white plate, but the caller places its own
 * [RentivoListDivider]s between rows. Prefer the `rows` overload, which places them for you.
 */
@Composable
fun RentivoListGroup(
  modifier: Modifier = Modifier,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .clip(ListGroupShape)
      .background(Color.White),
    content = content,
  )
}

/**
 * The hairline between two rows of a [RentivoListGroup], inset from the leading edge so it starts
 * under the row's text rather than at the plate's edge — the iOS separator inset.
 */
@Composable
fun RentivoListDivider(
  modifier: Modifier = Modifier,
  indent: Dp = RentivoSpacing.large,
) {
  HorizontalDivider(
    modifier = modifier.padding(start = indent),
    thickness = 1.dp,
    color = RentivoColors.separator,
  )
}

/**
 * The primary call to action: a solid, saturated fill with a bold white label, a 2dp ink border and
 * a hard 3dp shadow. Pressing dims the fill to 75%, collapses the shadow and slides the button
 * 3dp down-and-right, so it visually presses into its own shadow.
 *
 * [color] is used only with saturated accent tokens (`emerald`, `blue`, `coral`, and similar),
 * which keep the white label at >= 4.5:1. Passing a light token such as `paper` or `surface` here
 * would break that contrast — nothing enforces it.
 */
@Composable
fun RentivoButton(
  text: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.emerald,
  enabled: Boolean = true,
) {
  RentivoButton(onClick = onClick, modifier = modifier, color = color, enabled = enabled) {
    Text(
      text = text,
      style = RentivoTypography.cardTitle,
      color = if (enabled) Color.White else RentivoColors.secondaryInk,
      textAlign = TextAlign.Center,
    )
  }
}

/** Content-slot variant of [RentivoButton], for labels that need an icon or custom layout. */
@Composable
fun RentivoButton(
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.emerald,
  enabled: Boolean = true,
  content: @Composable RowScope.() -> Unit,
) {
  val interactionSource = remember { MutableInteractionSource() }
  val pressed by interactionSource.collectIsPressedAsState()
  // One animated value drives both halves of the press: the button slides in by `press` while the
  // shadow it sits on shrinks by the same amount, so at rest it is 3dp/0dp and fully pressed 0/3dp.
  val press by animateDpAsState(
    targetValue = if (pressed && enabled) ControlShadowOffset else 0.dp,
    animationSpec = tween(durationMillis = 80, easing = LinearOutSlowInEasing),
    label = "rentivoButtonPress",
  )
  // Disabled is a distinct plate, not a washed-out accent: a desaturated-and-dimmed green still
  // reads as "green button, just faded", where iOS renders an unmistakably inert gray control.
  // The border and the shadow go with it, so nothing about a disabled button invites a press.
  val resolvedFill = when {
    !enabled -> RentivoColors.disabledFill
    pressed -> color.copy(alpha = 0.75f)
    else -> color
  }

  Box(modifier = modifier.padding(end = ControlShadowOffset, bottom = ControlShadowOffset)) {
    Row(
      modifier = Modifier
        .offset(x = press, y = press)
        .then(
          if (enabled) {
            Modifier.rentivoHardShadow(offset = ControlShadowOffset - press, cornerRadius = 14.dp)
          } else {
            Modifier
          },
        )
        .clip(ControlShape)
        .background(resolvedFill)
        .then(
          if (enabled) {
            Modifier.border(width = BorderStroke, color = RentivoColors.ink, shape = ControlShape)
          } else {
            Modifier
          },
        )
        .clickable(
          interactionSource = interactionSource,
          indication = null,
          enabled = enabled,
          onClick = onClick,
        )
        .fillMaxWidth()
        .heightIn(min = 48.dp)
        .padding(horizontal = RentivoSpacing.medium, vertical = RentivoSpacing.small),
      horizontalArrangement = Arrangement.Center,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      // Slot content paints itself, so the only lever on a caller-supplied `Icon` or `Text` that
      // reads the ambient color is `LocalContentColor`. Providing it here means an unstyled slot
      // greys out with the plate instead of staying white on gray.
      CompositionLocalProvider(
        LocalContentColor provides if (enabled) Color.White else RentivoColors.secondaryInk,
        content = { content() },
      )
    }
  }
}

/**
 * The wordmark: an emerald rounded square holding a white "R", optionally followed by the
 * "rentivo" lettering. [compact] is the navigation-bar size; the default is the splash size.
 */
@Composable
fun BrandMark(
  compact: Boolean = false,
  modifier: Modifier = Modifier,
) {
  val glyphSize = if (compact) 20.sp else 30.sp
  val boxSize = if (compact) 34.dp else 48.dp
  val cornerRadius = if (compact) 9.dp else 13.dp
  val shape = RoundedCornerShape(cornerRadius)

  Row(
    modifier = modifier.clearAndSetSemantics { contentDescription = "Rentivo" },
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(
      modifier = Modifier
        .size(boxSize)
        .clip(shape)
        .background(RentivoColors.emerald)
        .border(width = BorderStroke, color = RentivoColors.ink, shape = shape),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        text = "R",
        color = Color.White,
        style = TextStyle(
          fontFamily = RentivoFontFamily,
          fontWeight = FontWeight.Black,
          fontSize = glyphSize,
        ),
      )
    }
    if (!compact) {
      Text(
        text = "rentivo",
        color = RentivoColors.ink,
        style = RentivoTypography.display,
      )
    }
  }
}

/** The status color each [BillStatus] renders in, across badges, charts and detail headers. */
val BillStatus.accentColor: Color
  get() = when (this) {
    BillStatus.DRAFT -> RentivoColors.secondaryInk
    BillStatus.PUBLISHED -> RentivoColors.lilac
    BillStatus.SENT -> RentivoColors.blue
    BillStatus.PAID -> RentivoColors.emerald
    BillStatus.CANCELLED -> RentivoColors.coral
    BillStatus.DELAYED_PAYMENT -> RentivoColors.amber
  }

/** A capsule carrying the PT-BR status label, tinted at 14% behind a 1.5dp stroke. */
@Composable
fun StatusBadge(
  status: BillStatus,
  modifier: Modifier = Modifier,
) {
  val color = status.accentColor
  val label = status.label
  Text(
    text = label,
    style = RentivoTypography.metadata,
    color = color,
    modifier = modifier
      .clip(CircleShape)
      .background(color.copy(alpha = 0.14f))
      .border(width = 1.5.dp, color = color, shape = CircleShape)
      .padding(horizontal = 10.dp, vertical = 6.dp)
      .semantics { contentDescription = "Status: $label" },
  )
}

/**
 * Renders a [Money] with monospaced digits so amounts line up column-wise.
 *
 * [minimumScaleFactor] mirrors SwiftUI's modifier of the same name: below 1f the text shrinks in
 * 5% steps until it fits or hits the floor.
 */
@Composable
fun MoneyText(
  money: Money,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.ink,
  style: TextStyle = RentivoTypography.money,
  minimumScaleFactor: Float = 1f,
  maxLines: Int = Int.MAX_VALUE,
  contentDescriptionOverride: String? = null,
) {
  val formatted = money.formatted()
  val label = contentDescriptionOverride ?: "Valor: $formatted"
  var scale by remember(formatted, style, minimumScaleFactor) { mutableFloatStateOf(1f) }
  val scaled = if (scale >= 1f) {
    style
  } else {
    style.copy(
      fontSize = style.fontSize * scale,
      lineHeight = if (style.lineHeight.isSpecified) style.lineHeight * scale else style.lineHeight,
    )
  }

  Text(
    text = formatted,
    modifier = modifier.semantics { contentDescription = label },
    color = color,
    style = scaled,
    maxLines = maxLines,
    onTextLayout = { result ->
      if (result.hasVisualOverflow && scale > minimumScaleFactor) {
        scale = maxOf(minimumScaleFactor, scale - 0.05f)
      }
    },
  )
}

/**
 * The universal loading contract: every screen holds its own [LoadState] and hands it here.
 *
 * [retry] is synchronous, unlike the iOS `() async -> Void`; screens pass
 * `retry = { scope.launch { load() } }`.
 */
@Composable
fun <T> PageStateView(
  state: LoadState<T>,
  modifier: Modifier = Modifier,
  emptyTitle: String = "Nada por aqui ainda",
  emptyMessage: String = "Crie o primeiro item para começar.",
  emptyIcon: ImageVector = Icons.Filled.AutoAwesome,
  emptyActionTitle: String? = null,
  emptyAction: (() -> Unit)? = null,
  retry: () -> Unit = {},
  content: @Composable (T) -> Unit,
) {
  when (state) {
    LoadState.Idle, LoadState.Loading -> Column(
      modifier = modifier
        .fillMaxSize()
        .testTag("page.loading"),
      verticalArrangement = Arrangement.Center,
      horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      CircularProgressIndicator(color = RentivoColors.emerald)
      Spacer(modifier = Modifier.height(RentivoSpacing.medium))
      Text(
        text = "Carregando…",
        style = RentivoTypography.subheadline,
        color = RentivoColors.secondaryInk,
      )
    }

    is LoadState.Loaded -> content(state.value)

    LoadState.Empty -> PageStatePlaceholder(
      modifier = modifier.testTag("page.empty"),
      icon = emptyIcon,
      title = emptyTitle,
      message = emptyMessage,
      actionTitle = emptyActionTitle,
      actionTag = "page.empty.action",
      action = emptyAction,
    )

    is LoadState.Failed -> PageStatePlaceholder(
      modifier = modifier.testTag("page.error"),
      icon = Icons.Outlined.WarningAmber,
      title = "Não foi possível carregar",
      message = state.error.message,
      actionTitle = "Tentar novamente",
      actionTag = "page.retry",
      action = retry,
    )
  }
}

@Composable
private fun PageStatePlaceholder(
  modifier: Modifier,
  icon: ImageVector,
  title: String,
  message: String,
  actionTitle: String?,
  actionTag: String,
  action: (() -> Unit)?,
) {
  Column(
    modifier = modifier
      .fillMaxSize()
      .padding(RentivoSpacing.page),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = RentivoColors.secondaryInk,
      modifier = Modifier.size(44.dp),
    )
    Spacer(modifier = Modifier.height(RentivoSpacing.medium))
    Text(
      text = title,
      style = RentivoTypography.title,
      color = RentivoColors.ink,
      textAlign = TextAlign.Center,
    )
    Spacer(modifier = Modifier.height(RentivoSpacing.small))
    Text(
      text = message,
      style = RentivoTypography.subheadline,
      color = RentivoColors.secondaryInk,
      textAlign = TextAlign.Center,
    )
    if (actionTitle != null && action != null) {
      Spacer(modifier = Modifier.height(RentivoSpacing.large))
      RentivoButton(
        text = actionTitle,
        onClick = action,
        modifier = Modifier
          .widthIn(max = 260.dp)
          .testTag(actionTag),
      )
    }
  }
}

/** The transient app-level message strip, rendered above the tab content. */
@Composable
fun NoticeBanner(
  notice: AppNotice,
  dismiss: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val color = when (notice.kind) {
    AppNotice.Kind.SUCCESS -> RentivoColors.emerald
    AppNotice.Kind.INFORMATION -> RentivoColors.blue
    AppNotice.Kind.WARNING -> RentivoColors.amber
  }
  val icon = when (notice.kind) {
    AppNotice.Kind.SUCCESS -> Icons.Filled.CheckCircle
    AppNotice.Kind.INFORMATION -> Icons.Filled.Info
    AppNotice.Kind.WARNING -> Icons.Filled.Warning
  }

  Row(
    modifier = modifier
      .fillMaxWidth()
      .padding(end = ControlShadowOffset, bottom = ControlShadowOffset)
      .rentivoHardShadow(offset = ControlShadowOffset, cornerRadius = 14.dp)
      .clip(ControlShape)
      .background(RentivoColors.surface)
      .border(width = BorderStroke, color = RentivoColors.ink, shape = ControlShape)
      .padding(RentivoSpacing.medium),
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.medium),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(imageVector = icon, contentDescription = null, tint = color)
    Text(
      text = notice.message,
      style = RentivoTypography.subheadlineEmphasized,
      color = RentivoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Icon(
      imageVector = Icons.Filled.Close,
      contentDescription = "Fechar aviso",
      tint = RentivoColors.ink,
      modifier = Modifier
        .clip(CircleShape)
        .clickable(onClick = dismiss)
        .padding(RentivoSpacing.tiny),
    )
  }
}

/**
 * An icon + title pair introducing a section of a scrolling screen.
 *
 * The icon is 28dp rather than Material's 24dp default, which pairs it with the 22sp title at the
 * same optical weight SwiftUI's `Label` gives a section header — a 24dp glyph next to this title
 * reads as undersized.
 */
@Composable
fun SectionTitle(
  title: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.small),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = RentivoColors.ink,
      modifier = Modifier.size(SectionTitleIconSize),
    )
    Text(text = title, style = RentivoTypography.title, color = RentivoColors.ink)
  }
}

/**
 * SwiftUI's `Label` for arbitrary text styles: an icon and a caption sized *from* the style rather
 * than at Material's fixed 24dp, so a metadata line gets a small glyph and a card title a large one
 * without every call site hand-tuning a `size()`.
 *
 * The 1.15 multiplier is what SF Symbols does at `.imageScale(.medium)`: the glyph sits slightly
 * above the cap height so it optically matches the text next to it.
 */
@Composable
fun IconLabel(
  text: String,
  icon: ImageVector,
  modifier: Modifier = Modifier,
  style: TextStyle = RentivoTypography.subheadline,
  tint: Color = RentivoColors.secondaryInk,
  textColor: Color = tint,
  maxLines: Int = Int.MAX_VALUE,
) {
  val iconSize = with(LocalDensity.current) { (style.fontSize * 1.15f).toDp() }
  Row(
    modifier = modifier,
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny + 2.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = tint,
      modifier = Modifier.size(iconSize),
    )
    Text(
      text = text,
      style = style,
      color = textColor,
      maxLines = maxLines,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

/**
 * The Android equivalent of a SwiftUI `.sheet`: a surface that rises over the *entire* screen,
 * including the floating tab bar, leaving only a strip of dimmed backdrop at the top.
 *
 * A `Dialog` rather than an in-tree overlay is what buys the "including the tab bar" part — the tab
 * bar lives in the root `Scaffold`, so nothing composed inside a tab can cover it. Two properties
 * make the dialog behave like a sheet instead of an alert: `usePlatformDefaultWidth = false` drops
 * the inset alert width so it can fill the display, and `decorFitsSystemWindows = false` lets it
 * extend under the status and navigation bars, which is what puts the sheet's rounded shoulders
 * against the scrim instead of against a system bar.
 *
 * Back dismisses the sheet and nothing else. [dismissEnabled] gates it for a sheet that must not be
 * abandoned mid-flight (an upload, say); the platform's own back handling is gated by the same flag,
 * so a disabled sheet swallows back rather than falling through to the screen underneath.
 */
@Composable
fun FullScreenSheet(
  onDismissRequest: () -> Unit,
  dismissEnabled: Boolean = true,
  content: @Composable () -> Unit,
) {
  val app = LocalAppModel.current
  // The sheet's own window reaches the bottom of the display, under the gesture-navigation pill,
  // but reports no window insets of its own to the composition inside it — so `navigationBarsPadding`
  // in there measures zero and the last row of a scrolling form ends up bisected by the pill. The
  // strip is therefore measured out here, in the host window, and applied as plain padding inside.
  val navigationBarInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

  Dialog(
    onDismissRequest = onDismissRequest,
    properties = DialogProperties(
      usePlatformDefaultWidth = false,
      dismissOnBackPress = dismissEnabled,
      dismissOnClickOutside = false,
      decorFitsSystemWindows = false,
    ),
  ) {
    // The dialog window owns the back dispatcher its content composes against, so this handler
    // takes the gesture ahead of `dismissOnBackPress` and never reaches the host activity — the
    // navigation stack behind the sheet stays exactly where it was.
    BackHandler(enabled = dismissEnabled, onBack = onDismissRequest)

    Column(modifier = Modifier.fillMaxSize()) {
      // The strip of scrim iOS leaves above a sheet. Sizing it to the status bar rather than a
      // fixed value keeps it right on a device with a large cutout.
      Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
      Box(
        modifier = Modifier
          .fillMaxSize()
          .clip(SheetShape)
          .background(RentivoColors.paper)
          // Inside the paper, never around it: the sheet fills the display to its bottom edge and
          // only its content stops short of the pill.
          .padding(bottom = navigationBarInset),
      ) {
        content()
        app.notice?.let { notice ->
          NoticeBanner(
            notice = notice,
            dismiss = { app.notice = null },
            modifier = Modifier
              .align(Alignment.TopCenter)
              .padding(horizontal = RentivoSpacing.page, vertical = RentivoSpacing.small),
          )
        }
      }
    }
  }
}

/**
 * A borderless text field for a row of a [RentivoListGroup]: no container, no outline and no
 * floating label, just the value sitting on the row's white plate the way iOS `TextField` inside a
 * `Form` does.
 *
 * The label belongs to the row, not the field — put a `Text` beside it — so the only affordance
 * here is [placeholder], drawn at 55% secondary ink to sit clearly below real content without
 * disappearing.
 *
 * [monospace] switches to the tabular face for values read character-by-character (API keys, hex
 * colors, recovery codes), where a proportional font makes `l`/`1` and `O`/`0` ambiguous.
 * [visualTransformation] carries password masking.
 */
@Composable
fun RentivoListField(
  value: String,
  onValueChange: (String) -> Unit,
  modifier: Modifier = Modifier,
  placeholder: String? = null,
  enabled: Boolean = true,
  singleLine: Boolean = true,
  monospace: Boolean = false,
  textAlign: TextAlign = TextAlign.Start,
  keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
  keyboardActions: KeyboardActions = KeyboardActions.Default,
  visualTransformation: VisualTransformation = VisualTransformation.None,
) {
  val base = if (monospace) {
    RentivoTypography.body.copy(fontFamily = FontFamily.Monospace)
  } else {
    RentivoTypography.body
  }
  val style = base.copy(
    color = if (enabled) RentivoColors.ink else RentivoColors.secondaryInk,
    textAlign = textAlign,
  )

  BasicTextField(
    value = value,
    onValueChange = onValueChange,
    modifier = modifier.fillMaxWidth(),
    enabled = enabled,
    textStyle = style,
    singleLine = singleLine,
    keyboardOptions = keyboardOptions,
    keyboardActions = keyboardActions,
    visualTransformation = visualTransformation,
    cursorBrush = SolidColor(RentivoColors.emerald),
    decorationBox = { field ->
      Box(
        contentAlignment = when (textAlign) {
          TextAlign.End -> Alignment.CenterEnd
          TextAlign.Center -> Alignment.Center
          else -> Alignment.CenterStart
        },
      ) {
        if (value.isEmpty() && placeholder != null) {
          Text(
            text = placeholder,
            style = style.copy(color = RentivoColors.secondaryInk.copy(alpha = 0.55f)),
            maxLines = if (singleLine) 1 else Int.MAX_VALUE,
            overflow = TextOverflow.Ellipsis,
          )
        }
        field()
      }
    },
  )
}

/**
 * SwiftUI's `.borderedProminent`: a flat emerald capsule with a plain white label.
 *
 * This is the *system* call to action, not the neo-brutalist [RentivoButton] — no ink outline, no
 * offset shadow, and a regular-weight label rather than a bold one. Use it where the iOS screen
 * uses a stock prominent button (sheet confirmations, empty-state actions); reach for
 * [RentivoButton] where the design leans on the brutalist card language.
 *
 * Disabled renders the same inert gray plate as [RentivoButton].
 */
@Composable
fun RentivoProminentButton(
  text: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  color: Color = RentivoColors.emerald,
) {
  RentivoProminentButton(onClick = onClick, modifier = modifier, enabled = enabled, color = color) {
    Text(text = text, style = RentivoTypography.body, textAlign = TextAlign.Center)
  }
}

/** Content-slot variant of [RentivoProminentButton], for labels that need an icon. */
@Composable
fun RentivoProminentButton(
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  color: Color = RentivoColors.emerald,
  content: @Composable RowScope.() -> Unit,
) {
  CapsuleButton(
    onClick = onClick,
    modifier = modifier,
    enabled = enabled,
    fill = color,
    contentColor = Color.White,
    content = content,
  )
}

/**
 * SwiftUI's `.bordered` with an accent tint: an emerald label on a pale emerald capsule.
 *
 * The secondary action next to a [RentivoProminentButton] — "Cancelar" beside "Salvar", a filter
 * chip, a row-level "Ver detalhes". Same flat capsule geometry, no outline and no shadow.
 */
@Composable
fun RentivoTonalButton(
  text: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  color: Color = RentivoColors.emerald,
  containerColor: Color = RentivoColors.emeraldLight,
) {
  RentivoTonalButton(
    onClick = onClick,
    modifier = modifier,
    enabled = enabled,
    color = color,
    containerColor = containerColor,
  ) {
    Text(text = text, style = RentivoTypography.body, textAlign = TextAlign.Center)
  }
}

/** Content-slot variant of [RentivoTonalButton], for labels that need an icon. */
@Composable
fun RentivoTonalButton(
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  color: Color = RentivoColors.emerald,
  containerColor: Color = RentivoColors.emeraldLight,
  content: @Composable RowScope.() -> Unit,
) {
  CapsuleButton(
    onClick = onClick,
    modifier = modifier,
    enabled = enabled,
    fill = containerColor,
    contentColor = color,
    content = content,
  )
}

/**
 * The shared body of the two flat capsule buttons. Pressing dims the fill rather than sliding the
 * button, because there is no shadow here to press into.
 */
@Composable
private fun CapsuleButton(
  onClick: () -> Unit,
  modifier: Modifier,
  enabled: Boolean,
  fill: Color,
  contentColor: Color,
  content: @Composable RowScope.() -> Unit,
) {
  val interactionSource = remember { MutableInteractionSource() }
  val pressed by interactionSource.collectIsPressedAsState()
  val resolvedFill = when {
    !enabled -> RentivoColors.disabledFill
    pressed -> fill.copy(alpha = 0.75f).compositeOver(RentivoColors.paper)
    else -> fill
  }

  Row(
    modifier = modifier
      .clip(CircleShape)
      .background(resolvedFill)
      .clickable(
        interactionSource = interactionSource,
        indication = null,
        enabled = enabled,
        onClick = onClick,
      )
      .heightIn(min = 44.dp)
      .padding(horizontal = RentivoSpacing.large, vertical = RentivoSpacing.small),
    horizontalArrangement = Arrangement.spacedBy(
      space = RentivoSpacing.small,
      alignment = Alignment.CenterHorizontally,
    ),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    CompositionLocalProvider(
      LocalContentColor provides if (enabled) contentColor else RentivoColors.secondaryInk,
      content = { content() },
    )
  }
}

/**
 * A `UISegmentedControl`: labels laid out edge to edge in a recessed gray groove, with the selected
 * one lifted onto a white pill.
 *
 * Deliberately not Material's `SingleChoiceSegmentedButtonRow`, which stamps a check mark into the
 * selected segment, outlines every segment and takes its active fill from `secondaryContainer`.
 *
 * Segments share the width equally and each label is held to a single unwrapped line, so a long
 * option ellipsizes inside its own segment instead of growing the control past its rounded track.
 * Keep the labels short (one or two words) — this is a filter switch, not a menu.
 */
@Composable
fun RentivoSegmentedPicker(
  options: List<String>,
  selectedIndex: Int,
  onSelect: (Int) -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(SegmentedTrackShape)
      .background(RentivoColors.segmentedTrack)
      .padding(SegmentedTrackPadding),
    horizontalArrangement = Arrangement.spacedBy(SegmentedTrackPadding),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    options.forEachIndexed { index, option ->
      val selected = index == selectedIndex
      Box(
        modifier = Modifier
          .weight(1f)
          .heightIn(min = 30.dp)
          .then(
            if (selected) {
              Modifier.shadow(elevation = 1.dp, shape = SegmentedPillShape)
            } else {
              Modifier
            },
          )
          .clip(SegmentedPillShape)
          .background(if (selected) Color.White else Color.Transparent)
          .clickable(enabled = enabled && !selected) { onSelect(index) }
          .padding(horizontal = RentivoSpacing.small, vertical = 6.dp),
        contentAlignment = Alignment.Center,
      ) {
        Text(
          text = option,
          style = if (selected) {
            RentivoTypography.subheadlineEmphasized
          } else {
            RentivoTypography.subheadline
          },
          color = if (enabled) RentivoColors.ink else RentivoColors.secondaryInk,
          maxLines = 1,
          softWrap = false,
          overflow = TextOverflow.Ellipsis,
          textAlign = TextAlign.Center,
        )
      }
    }
  }
}
