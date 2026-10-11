#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

struct NavigationVisualFixture: View {
    @State private var state = AppStateManager(persistsSelection: false)
    @State private var ready = false
    private static let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)

    var body: some View {
        Group {
            if ready { MainTabView() } else { ProgressView() }
        }
        .environment(state)
        .modelContainer(Self.container)
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("UITEST_VISUAL_DARK") ? .dark : .light)
        .task {
            guard !ready else { return }
            do {
                state.setOptionalTabs([.planning])
                let id = try await DemoDataService(modelContext: Self.container.mainContext).generateDemoData()
                let books = try Self.container.mainContext.fetch(FetchDescriptor<Account>())
                if let book = books.first(where: { $0.id == id }) { state.selectAccount(book) }
                ready = true
            } catch { assertionFailure(error.localizedDescription) }
        }
    }
}
#endif
