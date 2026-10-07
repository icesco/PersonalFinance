import SwiftUI
import SwiftData
import FinanceCore
import WidgetKit
import CoreData

@MainActor
enum WidgetSnapshotPublisher {
    static let preferenceKey = "widgets.showFinancialData"

    static func redact() { publish(.empty(.hidden)) }

    static func update(container: ModelContainer, protected: Bool) {
        guard !protected, UserDefaults.standard.bool(forKey: preferenceKey) else { redact(); return }
        let reader = ModelContext(container)
        do {
            let snapshot = try FinanceWidgetBuilder.build(
                accounts: reader.fetch(FetchDescriptor<Account>()), budgets: reader.fetch(FetchDescriptor<Budget>()),
                transactions: reader.fetch(FetchDescriptor<FinanceTransaction>()),
                resolutions: reader.fetch(FetchDescriptor<RecurrenceResolution>()))
            publish(snapshot)
        } catch { publish(.empty(.unavailable)) }
    }

    private static func publish(_ snapshot: FinanceWidgetSnapshot) {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("UITEST_MAC_LOCAL") else { return }
        #endif
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let url = FinanceWidgetStorage.sharedURL else { return }
        do { try FinanceWidgetStorage.write(snapshot, to: url) }
        catch {
            // Never leave an older financial snapshot behind after privacy is enabled.
            try? FileManager.default.removeItem(at: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: FinanceWidgetStorage.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: FinanceWidgetStorage.balanceKind)
    }
}

struct WidgetSnapshotObserver: View {
    var refreshSnapshot: @MainActor (ModelContainer, Bool) -> Void = { container, protected in
        WidgetSnapshotPublisher.update(container: container, protected: protected)
    }
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(AppLock.self) private var lock
    @AppStorage(WidgetSnapshotPublisher.preferenceKey) private var showsData = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task { update() }
            .onChange(of: showsData) { _, _ in update() }
            .onChange(of: lock.isEnabled) { _, _ in update() }
            .onChange(of: phase) { _, phase in if phase == .active { update() } }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { notification in
                guard let savedContext = notification.object as? ModelContext,
                      savedContext.container === context.container else { return }
                update()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in update() }
    }
    private func update() {
        refreshSnapshot(context.container, lock.isEnabled)
    }
}

struct WidgetSettingsSection: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(WidgetSnapshotPublisher.preferenceKey) private var showsData = false
    var body: some View {
        Section {
            Toggle("Mostra dati finanziari nei widget", isOn: $showsData)
                .disabled(lock.isEnabled)
                .onChange(of: showsData) { _, value in if !value { WidgetSnapshotPublisher.redact() } }
            if lock.isEnabled { Text("I dati nei widget sono nascosti perché il blocco di Formi è attivo.").font(.caption) }
        } header: { Text("Widget") } footer: {
            Text("Aggiungi Riepilogo Formi o Saldo per conto dalla galleria widget e scegli un libro. Per il saldo puoi scegliere anche il periodo. I dati si aggiornano quando apri o modifichi l’app; l’orario indica l’ultimo aggiornamento. Il sistema gestisce quando ridisegnare il widget. L’accesso Nuova spesa resta disponibile anche con i dati nascosti.")
        }
    }
}
