import SwiftUI
import FinanceCore

/// Scoped to an active, unlocked scene. Cancellation follows the scene/container lifetime.
struct SharedBookRefreshObserver: View {
    @Environment(DataStorageManager.self) private var storage
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var phase

    private struct Configuration: Equatable {
        let enabled: Bool
        let generation: Int
    }
    private var configuration: Configuration {
        Configuration(enabled: storage.isCloudSyncEnabled && !storage.isMigrating && !lock.isLocked && phase == .active,
                      generation: storage.containerGeneration)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: configuration) {
                guard configuration.enabled,
                      ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                while !Task.isCancelled {
                    await storage.sharedBookAutomaticRefresh.refresh()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
    }
}
