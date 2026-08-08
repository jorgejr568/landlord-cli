package app.rentivo.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

/**
 * Semantic color tokens, ported 1:1 from `ios/Rentivo/DesignSystem/RentivoTheme.swift`.
 *
 * The app renders in light appearance only (the iOS app pins `UIUserInterfaceStyle = Light`), so
 * each token is a single fixed sRGB value and there is no dark palette. Accent hues (`emerald`,
 * `amber`, `coral`, `blue`, `lilac`) are tuned so that, used as-is, they meet WCAG AA (>= 4.5:1) as
 * foreground text/icon color against both [paper] and [surface], AND against their own
 * 14%-opacity tint (the pattern `StatusBadge` uses). Do not nudge these values.
 */
object RentivoColors {
  val paper = Color(red = 0.97f, green = 0.95f, blue = 0.90f)
  val surface = Color(red = 1.00f, green = 0.99f, blue = 0.96f)
  val ink = Color(red = 0.12f, green = 0.12f, blue = 0.18f)
  val secondaryInk = Color(red = 0.34f, green = 0.34f, blue = 0.40f)

  val emerald = Color(red = 0.026f, green = 0.456f, blue = 0.318f)
  val emeraldLight = Color(red = 0.87f, green = 0.96f, blue = 0.93f)
  val amber = Color(red = 0.539f, green = 0.36f, blue = 0.093f)
  val coral = Color(red = 0.681f, green = 0.254f, blue = 0.205f)
  val blue = Color(red = 0.16f, green = 0.395f, blue = 0.714f)
  val lilac = Color(red = 0.446f, green = 0.346f, blue = 0.655f)
}

/** Layout rhythm. The Swift tokens are `CGFloat` points; the Android equivalents are `Dp`. */
object RentivoSpacing {
  val tiny = 4.dp
  val small = 8.dp
  val medium = 12.dp
  val large = 20.dp
  val page = 24.dp
  val section = 32.dp
}

/**
 * Text styles ported from the iOS `RentivoTypography` enum.
 *
 * iOS uses `design: .rounded` (SF Rounded), which has no Android counterpart, so the rounded,
 * friendly feel is approximated with the platform sans family at heavier weights. Only [money]
 * keeps a hard requirement: it must be monospaced so digits stay column-aligned across rows.
 *
 * Point sizes come from the iOS text styles at the default Dynamic Type size:
 * `largeTitle` 34, `title2` 22, `title3` 20, `headline` 17, `subheadline` 15, `caption` 12.
 */
object RentivoTypography {
  val display = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Black,
    fontSize = 34.sp,
    lineHeight = 41.sp,
  )

  val title = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Bold,
    fontSize = 22.sp,
    lineHeight = 28.sp,
  )

  val cardTitle = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Bold,
    fontSize = 17.sp,
    lineHeight = 22.sp,
  )

  val metadata = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.SemiBold,
    fontSize = 12.sp,
    lineHeight = 16.sp,
  )

  val money = TextStyle(
    fontFamily = FontFamily.Monospace,
    fontWeight = FontWeight.Bold,
    fontSize = 20.sp,
    lineHeight = 26.sp,
  )

  /** iOS `body`. Default copy inside cards. */
  val body = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Normal,
    fontSize = 17.sp,
    lineHeight = 22.sp,
  )

  /** iOS `subheadline`. Secondary copy, banner messages, list detail lines. */
  val subheadline = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Normal,
    fontSize = 15.sp,
    lineHeight = 20.sp,
  )

  /** iOS `subheadline.weight(.semibold)`. */
  val subheadlineEmphasized = subheadline.copy(fontWeight = FontWeight.SemiBold)

  /** iOS `caption`, unemphasized. */
  val caption = TextStyle(
    fontFamily = FontFamily.Default,
    fontWeight = FontWeight.Normal,
    fontSize = 12.sp,
    lineHeight = 16.sp,
  )

  /**
   * The Material 3 [Typography] the theme installs, so stock Material components pick up the
   * Rentivo styles. Rentivo-authored UI should reference the named tokens above directly.
   */
  val material = Typography(
    displayLarge = display,
    displayMedium = display,
    displaySmall = display,
    headlineLarge = display,
    headlineMedium = title,
    headlineSmall = title,
    titleLarge = title,
    titleMedium = cardTitle,
    titleSmall = cardTitle,
    bodyLarge = body,
    bodyMedium = subheadline,
    bodySmall = caption,
    labelLarge = cardTitle,
    labelMedium = metadata,
    labelSmall = metadata,
  )
}

/**
 * Light-only scheme. There is deliberately no dark variant: the palette above is a fixed
 * neo-brutalist set and the iOS app it mirrors renders in light appearance only.
 */
private val RentivoLightColorScheme = lightColorScheme(
  primary = RentivoColors.emerald,
  onPrimary = Color.White,
  primaryContainer = RentivoColors.emeraldLight,
  onPrimaryContainer = RentivoColors.ink,
  secondary = RentivoColors.blue,
  onSecondary = Color.White,
  tertiary = RentivoColors.lilac,
  onTertiary = Color.White,
  background = RentivoColors.paper,
  onBackground = RentivoColors.ink,
  surface = RentivoColors.surface,
  onSurface = RentivoColors.ink,
  surfaceVariant = RentivoColors.paper,
  onSurfaceVariant = RentivoColors.secondaryInk,
  error = RentivoColors.coral,
  onError = Color.White,
  outline = RentivoColors.ink,
  outlineVariant = RentivoColors.secondaryInk,
)

@Composable
fun RentivoTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = RentivoLightColorScheme,
    typography = RentivoTypography.material,
    content = content,
  )
}

/** The full-bleed page background. Mirrors the SwiftUI `View.rentivoPage()` extension. */
fun Modifier.rentivoPage(): Modifier = fillMaxSize().background(RentivoColors.paper)

/**
 * Formats a PT-BR count string with correct singular/plural noun agreement, e.g.
 * `ptBRCount(1, "fatura", "faturas")` -> "1 fatura" and
 * `ptBRCount(3, "fatura", "faturas")` -> "3 faturas".
 */
fun ptBRCount(count: Int, singular: String, plural: String): String =
  "$count ${if (count == 1) singular else plural}"

/**
 * The equivalent of Swift's `String.capitalized`: the first character of *every* space-separated
 * word is uppercased and the rest lowercased. A reference month therefore reads "Agosto De 2026",
 * exactly like iOS — capitalizing only the leading word would render a prettier "Agosto de 2026"
 * and silently diverge from the shipped copy.
 *
 * [Locale.ROOT] is deliberate: the strings are PT-BR copy, and the device locale must not change
 * how they are cased (a Turkish locale would otherwise dotless-i the result).
 */
fun String.capitalizedPTBR(): String = split(" ").joinToString(" ") { word ->
  word.lowercase(Locale.ROOT).replaceFirstChar { it.titlecase(Locale.ROOT) }
}
