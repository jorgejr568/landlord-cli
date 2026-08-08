package app.rentivo.features.bills

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import app.rentivo.domain.Bill
import app.rentivo.domain.BillID
import app.rentivo.domain.Billing

// Placeholder signatures for the bills feature port; replaced by the feature unit.

@Composable
fun BillDetailScreen(
    billing: Billing,
    billId: BillID,
    onMutation: suspend () -> Unit,
    onBack: () -> Unit,
) {
    Text("Fatura")
}

@Composable
fun BillFormSheet(
    billing: Billing,
    existing: Bill? = null,
    onSaved: suspend () -> Unit,
    onDismiss: () -> Unit,
) {
    Text("Gerar fatura")
}
