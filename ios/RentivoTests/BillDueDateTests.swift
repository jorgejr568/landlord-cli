import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

/// A fixed UTC calendar keeps the `DateOnly` <-> `Date` round trip independent of the
/// machine's time zone, which would otherwise shift the day across the midnight boundary.
private let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

@Test func defaultDueDateIsDayTenOfTheMonthAfterTheReferenceMonth() {
  // A bill covering July is normally paid in early August: the reference month and the due
  // date are independent, and the default has to reflect that rather than reusing the month.
  #expect(
    ReferenceMonth(year: 2026, month: 7).defaultDueDate == DateOnly(year: 2026, month: 8, day: 10)
  )
}

@Test func defaultDueDateRollsOverIntoTheNextYearForDecember() {
  #expect(
    ReferenceMonth(year: 2026, month: 12).defaultDueDate == DateOnly(year: 2027, month: 1, day: 10)
  )
}

@Test func dateOnlyRoundTripsThroughDate() {
  let original = DateOnly(year: 2026, month: 8, day: 10)
  #expect(DateOnly(from: original.resolvedDate(in: utcCalendar), calendar: utcCalendar) == original)
}

@Test func dateOnlyResolvesImpossibleComponentsWithoutTrapping() throws {
  // 31/02 can arrive from the wire via the failable ISO initializer, which only range-checks
  // the day as 1...31 without consulting the month's length. Resolving it must produce a date
  // rather than crash the picker that seeds from it; `Calendar` normalizes it into March.
  let impossible = try #require(DateOnly(iso8601String: "2026-02-31"))
  let resolved = impossible.resolvedDate(in: utcCalendar)
  #expect(utcCalendar.component(.month, from: resolved) == 3)
}
