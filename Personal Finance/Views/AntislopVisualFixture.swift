#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

/// Isolated simulator routes exercise the production views and their recovery actions.
struct AntislopVisualFixture: View {
    @State private var state = AppStateManager()
    @State private var route: Route?
    @State private var ready = false
    private static let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
    private static let emptyContainer = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
    private static let emptyState = AppStateManager()
    private static let file: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anti-slop-prova.csv")
        try! "Data,Conto,Importo,Descrizione\n2026-10-01,Banca,-24.50,Spesa di prova\n2026-10-02,Risparmio,100,Versamento di prova\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }()
    private enum Route: String, Identifiable {
        case csv, filteredCSV, export, demo, home
        var id: String { rawValue }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Schermate reali · dati di prova") {
                    Button("Importa CSV") { route = .csv }
                    Button("CSV con due conti") { route = .filteredCSV }
                    Button("Errore esportazione CSV") { route = .export }
                    Button("Errore creazione demo") { route = .demo }
                    Button("Home: aggiornamento fallito") { route = .home }
                }
            }
            .navigationTitle("Verifica Formi")
            .disabled(!ready)
            .sheet(item: $route) { route in
                switch route {
                case .csv: CSVImportView()
                case .filteredCSV: CSVImportView(initialFileForTesting: Self.file)
                case .export: AntislopExportRoute()
                case .demo:
                    OnboardingView(demoSaveForTesting: { _ in throw AntislopFailure.simulated })
                        .modelContainer(Self.emptyContainer)
                        .environment(Self.emptyState)
                case .home: AntislopHomeRoute()
                }
            }
        }
        .modelContainer(Self.container)
        .environment(state)
        .task {
            guard !ready else { return }
            do {
                let id = try await DemoDataService(modelContext: Self.container.mainContext).generateDemoData()
                let accounts = try Self.container.mainContext.fetch(FetchDescriptor<Account>())
                if let account = accounts.first(where: { $0.id == id }) { state.selectAccount(account) }
                ready = true
            } catch { assertionFailure(error.localizedDescription) }
        }
    }
}

private enum AntislopFailure: LocalizedError {
    case simulated
    var errorDescription: String? { "Errore simulato per la verifica dell’interfaccia." }
}

private struct AntislopExportRoute: View {
    @Environment(\.modelContext) private var context
    @State private var failedOnce = false
    var body: some View {
        CSVExportView(fetchTransactionsForTesting: {
            if !failedOnce { failedOnce = true; throw AntislopFailure.simulated }
            return try context.fetch(FetchDescriptor<FinanceTransaction>())
        })
    }
}

private actor AntislopHomeReader {
    let reader = TodaySnapshotReader()
    var failNext = false
    func armFailure() { failNext = true }
    func load(_ container: ModelContainer, _ accountID: UUID?, _ all: Bool) async throws -> TodaySnapshot {
        if failNext { failNext = false; throw AntislopFailure.simulated }
        return try await reader.load(container: container, accountID: accountID, showAllAccounts: all)
    }
}

private struct AntislopHomeRoute: View {
    @State private var reader = AntislopHomeReader()
    var body: some View {
        TodayView(loadSnapshotForTesting: { container, id, all in try await reader.load(container, id, all) })
            .task {
                try? await Task.sleep(for: .seconds(3))
                await reader.armFailure()
                NotificationCenter.default.post(name: .cloudSyncDidComplete, object: nil)
            }
    }
}
#endif
