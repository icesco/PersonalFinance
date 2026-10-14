import SwiftUI
import SwiftData
import FinanceCore

struct SharedCategoriesOverview: View {
    let book: Account?
    @Environment(AppStateManager.self) private var appState
    @Query private var allConti: [Conto]
    @State private var selectedContoID: UUID?

    private var conti: [Conto] {
        guard let book else { return [] }
        return allConti.filter { $0.account?.id == book.id && $0.usesSharedCategories == true && $0.isActive == true }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }

    private var selectedConto: Conto? {
        conti.first { $0.id == selectedContoID } ?? conti.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selectedConto {
                CategoryListManagementView(sharedConto: selectedConto, sharedConti: conti,
                                           onSelectSharedConto: { selectedContoID = $0.id })
                    .id(selectedConto.id)

            } else {
                ContentUnavailableView("Nessuna categoria condivisa", systemImage: "person.2",
                    description: Text(book == nil ? "Scegli un libro per vedere le categorie dei suoi conti condivisi." : "Quando condividi un conto di questo libro, il suo elenco di categorie compare qui."))
                if book == nil { Button("Scegli un libro") { appState.presentAccountSelection() } }
            }
        }
        .themedBackground()
        .tint(ForgiaPalette.accent)
    }
}
