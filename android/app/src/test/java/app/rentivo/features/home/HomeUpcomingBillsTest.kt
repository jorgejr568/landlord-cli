package app.rentivo.features.home

import app.rentivo.domain.Bill
import app.rentivo.domain.BillID
import app.rentivo.domain.BillStatus
import app.rentivo.domain.BillingID
import app.rentivo.domain.DateOnly
import app.rentivo.domain.ReferenceMonth
import org.junit.Assert.assertEquals
import org.junit.Test

class HomeUpcomingBillsTest {

  @Test
  fun `keeps only the bills still awaiting payment`() {
    val bills = BillStatus.entries.map { status -> bill(id = status.wire, status = status) }

    val kept = upcomingBills(bills).map { it.status }

    assertEquals(listOf(BillStatus.DRAFT, BillStatus.PUBLISHED, BillStatus.SENT), kept)
  }

  @Test
  fun `orders by due date and sends undated bills to the end`() {
    val undated = bill(id = "undated", dueDate = null)
    val later = bill(id = "later", dueDate = DateOnly(year = 2026, month = 9, day = 10))
    val sooner = bill(id = "sooner", dueDate = DateOnly(year = 2026, month = 8, day = 10))

    val ordered = upcomingBills(listOf(undated, later, sooner)).map { it.id.rawValue }

    assertEquals(listOf("sooner", "later", "undated"), ordered)
  }

  private fun bill(
    id: String,
    status: BillStatus = BillStatus.SENT,
    dueDate: DateOnly? = DateOnly(year = 2026, month = 8, day = 10),
  ) = Bill(
    id = BillID(rawValue = id),
    billingID = BillingID(rawValue = "billing"),
    referenceMonth = ReferenceMonth(year = 2026, month = 8),
    dueDate = dueDate,
    paidAt = null,
    notes = "",
    status = status,
    lineItems = emptyList(),
    receipts = emptyList(),
  )
}
