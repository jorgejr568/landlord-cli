package app.rentivo.designsystem

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/**
 * Placeholder Material 3 theme. The real Rentivo palette, typography and shapes
 * still have to be ported from the SwiftUI app.
 */
private val RentivoLightColorScheme = lightColorScheme()

@Composable
fun RentivoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = RentivoLightColorScheme,
        content = content,
    )
}
