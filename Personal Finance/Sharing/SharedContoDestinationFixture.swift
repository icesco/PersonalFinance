#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct SharedContoDestinationFixture: View {
    @State private var storage = DataStorageManager.makeLocalTestStorage()
    @State private var scope: SharedBookScope?
    @State private var receivedBookID: UUID?
    @State private var completedID: UUID?

    var body: some View {
        Group {
            if let container = storage.currentContainer, let scope, let receivedBookID {
                if let completedID {
                    DestinationResult(bookID: completedID).modelContainer(container)
                } else {
                    SharedContoDestinationView(scope: scope, receivedBookID: receivedBookID, title: "Casa") {
                        completedID = $0
                    }
                    .environment(storage)
                    .modelContainer(container)
                }
            } else { ProgressView() }
        }
        .task {
            guard scope == nil else { return }
            try! await storage.initializeContainer()
            let owner = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
            let book = Account(name: "Privato del proprietario")
            let house = Conto(name: "Casa", type: .checking, initialBalance: 100)
            house.account = book; owner.mainContext.insert(book); owner.mainContext.insert(house)
            try! owner.mainContext.save()
            let scope = try! SharedBookOwnerRegistration.register(bookID: book.id, contoID: house.id, ownerRecordName: "owner", container: owner)
            let snapshot = try! SharedBookParticipantExporter.export(scope: scope, container: owner)
            let target = storage.currentContainer!
            let received = try! SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: [:], container: target)
            target.mainContext.insert(Account(name: "Personale", currency: "EUR"))
            target.mainContext.insert(Account(name: "Dollari", currency: "USD"))
            try! target.mainContext.save()
            receivedBookID = received; self.scope = scope
        }
    }
}

private struct DestinationResult: View {
    let bookID: UUID
    @Query private var books: [Account]
    @Query private var conti: [Conto]
    var body: some View {
        List {
            Text("Conto aggiunto")
            Text(books.first { $0.id == bookID }?.name ?? "Libro")
                .accessibilityIdentifier("accepted-conto-book")
            Text("\(conti.count) conto")
            Text("\(books.count) libri")
        }
    }
}
#endif
