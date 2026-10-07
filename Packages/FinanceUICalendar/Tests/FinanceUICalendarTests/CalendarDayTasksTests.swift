import XCTest
import SwiftUI
@testable import FinanceUICalendar

final class CalendarDayTasksTests: XCTestCase {
    func testGroupingPreservesInsertionOrder() {
        let water = CalendarTask(id: "1", categoryID: "water", categoryLabel: "Annaffia", categoryIcon: "drop.fill", categoryColor: .blue, title: "Monstera")
        let fert = CalendarTask(id: "2", categoryID: "fert", categoryLabel: "Concima", categoryIcon: "leaf.fill", categoryColor: .green, title: "Ficus")
        let water2 = CalendarTask(id: "3", categoryID: "water", categoryLabel: "Annaffia", categoryIcon: "drop.fill", categoryColor: .blue, title: "Pothos")

        let day = CalendarDayTasks(date: Date(), tasks: [water, fert, water2])

        XCTAssertEqual(day.groups.count, 2)
        XCTAssertEqual(day.groups[0].id, "water")
        XCTAssertEqual(day.groups[0].tasks.count, 2)
        XCTAssertEqual(day.groups[1].id, "fert")
        XCTAssertEqual(day.groups[1].tasks.count, 1)
    }

    func testEmpty() {
        let day = CalendarDayTasks(date: Date(), tasks: [])
        XCTAssertTrue(day.isEmpty)
    }
}
