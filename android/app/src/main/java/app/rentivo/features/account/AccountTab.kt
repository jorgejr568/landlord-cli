package app.rentivo.features.account

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoTypography

/** Placeholder for the Conta tab; replaced by the ported `AccountView` navigation stack. */
@Composable
fun AccountTab() {
  Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Text(text = "Conta", style = RentivoTypography.title, color = RentivoColors.ink)
  }
}
