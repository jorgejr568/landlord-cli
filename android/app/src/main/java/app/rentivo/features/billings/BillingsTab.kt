package app.rentivo.features.billings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoTypography

/** Placeholder for the Cobranças tab; replaced by the ported `BillingListView` navigation stack. */
@Composable
fun BillingsTab() {
  Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    Text(text = "Cobranças", style = RentivoTypography.title, color = RentivoColors.ink)
  }
}
