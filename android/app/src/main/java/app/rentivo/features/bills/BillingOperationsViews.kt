package app.rentivo.features.bills

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import app.rentivo.domain.Bill
import app.rentivo.domain.Billing

// Placeholder signatures for the billing operations port; replaced by the feature unit.

@Composable
fun BillingOperationsLinks(
    billing: Billing,
    onOpenExpenses: () -> Unit,
    onOpenAttachments: () -> Unit,
    onOpenExport: () -> Unit,
) {
    Text("Operações")
}

@Composable
fun ExpenseListScreen(billing: Billing, onBack: () -> Unit) {
    Text("Despesas")
}

@Composable
fun AttachmentListScreen(billing: Billing, onBack: () -> Unit) {
    Text("Arquivos")
}

@Composable
fun ExportScreen(billing: Billing, onBack: () -> Unit) {
    Text("Exportar")
}

@Composable
fun CommunicationComposerSheet(billing: Billing, bill: Bill, onDismiss: () -> Unit) {
    Text("Enviar comunicação")
}
