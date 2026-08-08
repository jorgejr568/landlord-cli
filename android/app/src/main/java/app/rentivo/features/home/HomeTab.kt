package app.rentivo.features.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.material3.Text
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoTypography

/** Placeholder for the Início tab; replaced by the ported `HomeView` navigation stack. */
@Composable
fun HomeTab() {
  Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Text(text = "Início", style = RentivoTypography.title, color = RentivoColors.ink)
  }
}
