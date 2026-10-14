#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct SharedContoFixture: View {
    @State private var appState = AppStateManager()
    private static let data: (ModelContainer, Conto) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale")
        let personal = Conto(name: "Conto personale", type: .checking, initialBalance: 2000)
        let house = Conto(name: "Casa", type: .checking, initialBalance: 100)
        personal.account = book; house.account = book; book.conti = [personal, house]
        container.mainContext.insert(book)
        if ProcessInfo.processInfo.arguments.contains("UITEST_CATEGORY_PERSONAL_ONLY") {
            let category = FinanceCategory(name: "Categoria privata"); category.account = book
            container.mainContext.insert(category)
            try! container.mainContext.save()
            return (container, house)
        }
        let marco = TransactionPerson(id: "marco", name: "Marco")
        let anna = TransactionPerson(id: "anna", name: "Anna")
        let first = FinanceTransaction.createTransfer(amount: 500, fromConto: personal, toConto: house,
            transactionDescription: "Versamento per le spese di casa")
        first.createdByJSON = marco.encoded; first.lastEditedByJSON = marco.encoded; first.contributor = marco; first.assignedTo = anna
        let second = FinanceTransaction(amount: 400, type: .transfer, transactionDescription: "Versamento di Anna")
        second.setToConto(house); second.createdByJSON = marco.encoded; second.lastEditedByJSON = marco.encoded; second.contributor = anna
        container.mainContext.insert(first); container.mainContext.insert(second)
        house.usesSharedCategories = true
        let privateCategory = FinanceCategory(name: "Categoria privata"); privateCategory.account = book
        let sharedCategory = FinanceCategory(name: "Alimentari"); sharedCategory.account = book; sharedCategory.sharedContoID = house.id
        container.mainContext.insert(privateCategory); container.mainContext.insert(sharedCategory)
        let sharedChild = FinanceCategory(name: "Supermercato", parentCategoryId: sharedCategory.id)
        sharedChild.account = book; sharedChild.sharedContoID = house.id
        container.mainContext.insert(sharedChild)
        let expense = FinanceTransaction(amount: 40, type: .expense, transactionDescription: "Spesa casa")
        expense.setFromConto(house); expense.setCategory(sharedCategory); container.mainContext.insert(expense)
        let scope = SharedBookScope(ownerName: "marco", bookID: house.id, isContoShare: true)
        let membership = SharedBookMembership(scopeKey: scope.key, ownerName: scope.ownerName, remoteBookID: house.id, localBookID: book.id, isOwner: true)
        membership.localContoID = house.id
        membership.peopleJSON = String(data: try! JSONEncoder().encode([marco, anna]), encoding: .utf8)
        container.mainContext.insert(membership)
        if ProcessInfo.processInfo.arguments.contains("UITEST_CATEGORY_EMPTY_SHARED") {
            expense.setCategory(nil)
            container.mainContext.delete(sharedChild)
            container.mainContext.delete(sharedCategory)
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_CATEGORY_MULTI_CONTO") {
            let travel = Conto(name: "Viaggi", type: .checking)
            travel.account = book; travel.usesSharedCategories = true
            container.mainContext.insert(travel)
            let category = FinanceCategory(name: "Trasporti", icon: "airplane", kind: .expense)
            category.account = book; category.sharedContoID = travel.id
            container.mainContext.insert(category)
            let travelScope = SharedBookScope(ownerName: "luca", bookID: travel.id, isContoShare: true)
            let travelMember = SharedBookMembership(scopeKey: travelScope.key, ownerName: travelScope.ownerName,
                remoteBookID: travel.id, localBookID: book.id, isOwner: false)
            travelMember.localContoID = travel.id
            travelMember.peopleJSON = String(data: try! JSONEncoder().encode([marco, TransactionPerson(id: "luca", name: "Luca")]), encoding: .utf8)
            container.mainContext.insert(travelMember)
        }
        try! container.mainContext.save()
        return (container, house)
    }()

    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.arguments.contains("UITEST_CATEGORY_SCOPE") { CategoryManagementView() }
            else { FinanceContoDetailsView(conto: Self.data.1) }
        }
            .modelContainer(Self.data.0)
            .environment(appState)
            .onAppear { if let book = Self.data.1.account, appState.selectedAccount?.id != book.id { appState.selectAccount(book) } }
    }
}
#endif
