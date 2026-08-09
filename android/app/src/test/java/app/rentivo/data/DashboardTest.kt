package app.rentivo.data

import app.rentivo.domain.Bill
import app.rentivo.domain.BillStatus
import app.rentivo.domain.Money
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DashboardTest {

  @Test
  fun dashboardSummaryIsDerivedFromAuthoritativeRecords() = runTest {
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val summary = store.dashboardSummary()
    val billings = store.listBillings()
    var paid = Money.zero
    var delayed = Money.zero
    var expenses = Money.zero

    for (billing in billings) {
      for (bill in store.listBills(billingID = billing.id)) {
        if (bill.status == BillStatus.PAID) paid += bill.total
        if (bill.status == BillStatus.DELAYED_PAYMENT) delayed += bill.total
      }
      for (expense in store.listExpenses(billingID = billing.id)) {
        expenses += expense.amount
      }
    }

    assertEquals(paid, summary.received)
    assertEquals(delayed, summary.overdue)
    assertEquals(expenses, summary.expenses)
    assertEquals(paid - expenses, summary.netIncome)
    assertTrue(summary.collectionRatePercent > 0)
    assertTrue(summary.collectionRatePercent < 100)
  }

  @Test
  fun collectionRateIsComputedWithIntegerMathOnly() = runTest {
    // No floating point: paid * 100 / non-cancelled count, matching the live store.
    val store = MockRentivoStore(fixtures = MockFixtures.canonical)
    val summary = store.dashboardSummary()
    val billings = store.listBillings()
    val allBills = mutableListOf<Bill>()
    for (billing in billings) {
      allBills.addAll(store.listBills(billingID = billing.id))
    }
    val activeBills = allBills.filter { it.status != BillStatus.CANCELLED }
    val paidCount = activeBills.count { it.status == BillStatus.PAID }
    val expectedRate =
      if (activeBills.isEmpty()) 0 else (paidCount * 100) / activeBills.size

    assertEquals(expectedRate, summary.collectionRatePercent)
  }
}
