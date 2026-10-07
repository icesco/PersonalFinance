#if os(iOS)
import SwiftUI
import SwiftData
import CoreData

struct WatchSnapshotObserver: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(AppLock.self) private var lock
    @AppStorage(WatchPhoneBridge.preferenceKey) private var showsData = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task { update() }
            .onChange(of: showsData) { _, _ in update() }
            .onChange(of: lock.isEnabled) { _, _ in update() }
            .onChange(of: phase) { _, phase in if phase == .active { update() } }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { notification in
                guard let saved = notification.object as? ModelContext, saved.container === context.container else { return }
                update()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in update() }
    }
    private func update() { WatchPhoneBridge.shared.refresh(container: context.container, protected: lock.isEnabled) }
}

struct WatchSettingsSection: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(WatchPhoneBridge.preferenceKey) private var showsData = false
    var body: some View {
        Section {
            Toggle("Mostra riepilogo su Apple Watch", isOn: $showsData)
                .disabled(lock.isEnabled)
            Text("Dal Watch puoi scegliere conto e categoria, controllare i budget e confermare una spesa. iPhone deve essere raggiungibile.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Apple Watch") } footer: {
            Text("Il riepilogo contiene conti, categorie, budget, spese del mese e numero di scadenze. Il blocco di Formi lo nasconde. Le modifiche alla privacy raggiungono il Watch alla successiva connessione.")
        }
    }
}
#endif
