package app.rentivo.designsystem

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import app.rentivo.app.AppNotice
import app.rentivo.domain.BillStatus
import app.rentivo.domain.LoadState
import app.rentivo.domain.Money

private val CardShape = RoundedCornerShape(18.dp)
private val ControlShape = RoundedCornerShape(14.dp)

private val CardShadowOffset = 4.dp
private val ControlShadowOffset = 3.dp

/** Every bordered surface in the system uses the same 2dp ink outline. */
private val BorderStroke = 2.dp

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
 */
@Composable
fun RentivoCard(
  modifier: Modifier = Modifier,
  contentPadding: PaddingValues = PaddingValues(RentivoSpacing.large),
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      // Reserve the space the offset shadow paints into, mirroring the iOS trailing/bottom padding.
      .padding(end = CardShadowOffset, bottom = CardShadowOffset)
      .rentivoHardShadow(offset = CardShadowOffset, cornerRadius = 18.dp)
      .clip(CardShape)
      .background(RentivoColors.surface)
      .border(width = BorderStroke, color = RentivoColors.ink, shape = CardShape)
      .padding(contentPadding),
    content = content,
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
      color = Color.White,
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
  val fill = if (pressed && enabled) color.copy(alpha = 0.75f) else color
  // SwiftUI's disabled affordance is `.opacity(0.45).saturation(0.6)`; saturation leaves the white
  // label untouched, so desaturating the fill alone is the faithful equivalent here.
  val resolvedFill = if (enabled) fill else fill.desaturated(0.6f)

  Box(
    modifier = modifier
      .padding(end = ControlShadowOffset, bottom = ControlShadowOffset)
      .alpha(if (enabled) 1f else 0.45f),
  ) {
    Row(
      modifier = Modifier
        .offset(x = press, y = press)
        .rentivoHardShadow(offset = ControlShadowOffset - press, cornerRadius = 14.dp)
        .clip(ControlShape)
        .background(resolvedFill)
        .border(width = BorderStroke, color = RentivoColors.ink, shape = ControlShape)
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
      content = content,
    )
  }
}

/** Mixes a color toward its own luminance, the analog of SwiftUI's `.saturation(fraction)`. */
private fun Color.desaturated(fraction: Float): Color {
  val luminance = 0.299f * red + 0.587f * green + 0.114f * blue
  fun mix(channel: Float) = luminance + (channel - luminance) * fraction
  return Color(red = mix(red), green = mix(green), blue = mix(blue), alpha = alpha)
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
          fontFamily = FontFamily.Default,
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

/** An icon + title pair introducing a section of a scrolling screen. */
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
    Icon(imageVector = icon, contentDescription = null, tint = RentivoColors.ink)
    Text(text = title, style = RentivoTypography.title, color = RentivoColors.ink)
  }
}
