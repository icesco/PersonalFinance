import Foundation
import XCTest
@testable import FinanceUICalendar

final class MonthGridDatesTests: XCTestCase {
    func testGridRespectsFirstWeekdayAndContainsEveryMonthDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.firstWeekday = 2
        let date = calendar.date(from: .init(year: 2026, month: 10, day: 7))!
        let days = monthGridDates(containing: date, calendar: calendar)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(Set(days).count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), 2)
        XCTAssertEqual(days.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }.count, 31)
        calendar.firstWeekday = 1
        XCTAssertEqual(calendar.component(.weekday, from: monthGridDates(containing: date, calendar: calendar)[0]), 1)
    }
    func testDSTKeepsEveryCellAtLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let date = calendar.date(from: .init(year: 2026, month: 10, day: 7))!
        let days = monthGridDates(containing: date, calendar: calendar)
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        for pair in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: pair.0, to: pair.1).day, 1)
        }
        XCTAssertTrue(zip(days, days.dropFirst()).contains { $0.1.timeIntervalSince($0.0) == 25 * 3600 })
    }
}
