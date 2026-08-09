package app.rentivo.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BillDueDateTest {

  @Test
  fun defaultDueDateIsDayTenOfTheMonthAfterTheReferenceMonth() {
    // A bill covering July is normally paid in early August: the reference month and the due date
    // are independent, and the default has to reflect that rather than reusing the month.
    assertEquals(
      DateOnly(year = 2026, month = 8, day = 10),
      ReferenceMonth(year = 2026, month = 7).defaultDueDate,
    )
  }

  @Test
  fun defaultDueDateRollsOverIntoTheNextYearForDecember() {
    assertEquals(
      DateOnly(year = 2027, month = 1, day = 10),
      ReferenceMonth(year = 2026, month = 12).defaultDueDate,
    )
  }

  @Test
  fun dateOnlyRoundTripsThroughLocalDate() {
    val original = DateOnly(year = 2026, month = 8, day = 10)
    assertEquals(original, DateOnly.from(original.resolvedDate()))
  }

  @Test
  fun dateOnlyResolvesImpossibleComponentsWithoutTrapping() {
    // 31/02 can arrive from the wire via the failable ISO parser, which only range-checks the day
    // as 1..31 without consulting the month's length. Resolving it must produce a date rather than
    // throw in the picker that seeds from it; day-of-month arithmetic normalizes it into March.
    val impossible = DateOnly.fromIso8601String("2026-02-31")
    assertNotNull(impossible)
    assertEquals(3, impossible!!.resolvedDate().monthValue)
  }

  @Test
  fun billsCarryANullDueDateInsteadOfTheEpoch() {
    // A `null` due_date used to become 1970-01-01 and render as "Vence 01/01/1970"; the domain
    // models it as an honest absence.
    val bill = Bill(
      id = StableID.billDraft,
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 7),
      dueDate = null,
      paidAt = null,
      notes = "",
      status = BillStatus.DRAFT,
      lineItems = emptyList(),
      receipts = emptyList(),
    )

    assertNull(bill.dueDate)
    assertNull(
      BillDraft(
        billingID = StableID.billingAurora101,
        referenceMonth = ReferenceMonth(year = 2026, month = 7),
        dueDate = null,
        notes = "",
        lineItems = emptyList(),
      ).dueDate
    )
  }

  @Test
  fun aDueDateMayFallOutsideTheReferenceMonth() {
    // The whole point of the model: a July bill can be due in August.
    val draft = BillDraft(
      billingID = StableID.billingAurora101,
      referenceMonth = ReferenceMonth(year = 2026, month = 7),
      dueDate = DateOnly(year = 2026, month = 8, day = 10),
      notes = "",
      lineItems = emptyList(),
    )

    assertEquals("2026-07", draft.referenceMonth.apiValue)
    assertEquals("2026-08-10", draft.dueDate?.iso8601)
  }
}
