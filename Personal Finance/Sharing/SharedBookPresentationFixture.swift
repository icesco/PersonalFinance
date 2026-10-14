#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct SharedBookPresentationFixture: View {
    private static let data: (container: ModelContainer, book: Account, conto: Conto) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Casa e famiglia")
        let conto = Conto(name: "Spese di casa", type: .checking)
        conto.account = book
        book.conti = [conto]
        container.mainContext.insert(book)
        if ProcessInfo.processInfo.arguments.contains("UITEST_SHARING_RECEIVED") {
            let isConto = ProcessInfo.processInfo.arguments.contains("UITEST_SHARING_ACCOUNT")
            let scope = SharedBookScope(ownerName: "demo-owner", bookID: UUID(), isContoShare: isConto)
            let membership = SharedBookMembership(scopeKey: scope.key, ownerName: scope.ownerName,
                remoteBookID: scope.bookID, localBookID: book.id, isOwner: false)
            membership.localContoID = isConto ? conto.id : nil
            container.mainContext.insert(membership)
        }
        try! container.mainContext.save()
        return (container, book, conto)
    }()

    var body: some View {
        NavigationStack {
            SharedBookView(book: Self.data.book,
                           conto: ProcessInfo.processInfo.arguments.contains("UITEST_SHARING_ACCOUNT") ? Self.data.conto : nil)
        }
        .modelContainer(Self.data.container)
        .environment(\.locale, Locale(identifier: "it_IT"))
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("UITEST_SHARING_LARGE_TEXT") ? .accessibility3 : .large)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
    }
}
#endif
