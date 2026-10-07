import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct CategoryFilterTests {
    @Test func narrowsMacroAndPreservesOtherFamilies() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let food = Category(name: "Cibo")
        let restaurant = Category(name: "Ristoranti", parentCategoryId: food.id)
        let bar = Category(name: "Bar", parentCategoryId: food.id)
        let travel = Category(name: "Viaggi")
        for category in [food, restaurant, bar, travel] { context.insert(category) }
        let hierarchy = CategoryHierarchy(categories: [food, restaurant, bar, travel])
        let narrowed = hierarchy.toggling(restaurant, in: [food.id, travel.id])
        #expect(narrowed == [restaurant.id, travel.id])
        #expect(hierarchy.expanding(narrowed) == [restaurant.id, travel.id])
        let widened = hierarchy.toggling(food, in: [restaurant.id, bar.id, travel.id])
        #expect(widened == [food.id, travel.id])
        #expect(hierarchy.expanding(widened) == [food.id, restaurant.id, bar.id, travel.id])
        #expect(hierarchy.toggling(food, in: widened) == [travel.id])
        bar.isActive = false
        #expect(hierarchy.expanding([food.id]).contains(bar.id))
    }
}
