//
//  ContentView.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appState = AppStateManager()
    @Query private var accounts: [Account]

    var body: some View {
        ZStack {
            if accounts.isEmpty {
                // First launch or after factory reset: show onboarding
                OnboardingView()
                    .environment(appState)
            } else if appState.requiresAccountSelection(accounts: accounts) {
                // Show account selection modal
                AccountSelectionModal()
                    .environment(appState)
            } else {
                // Show main tab interface
                MainTabView()
                    .environment(appState)
                    .sheet(isPresented: Binding(
                        get: { appState.showingAccountCreation },
                        set: { _ in appState.dismissAccountCreation() }
                    )) {
                        CreateAccountView { newAccount in
                            appState.selectAccount(newAccount)
                        }
                        .environment(appState)
                    }
            }
        }
        .background { RecurrenceReminderObserver() }
        .background { WidgetSnapshotObserver() }
        #if os(iOS)
        .background { WatchSnapshotObserver() }
        #endif
        .tint(appState.themeManager.currentTheme.color)
        .environment(\.locale, Locale(identifier: "it_IT"))
        .onAppear {
            initializeAppState()
        }
        .onChange(of: accounts) { _, newAccounts in
            // Handle account changes (creation, deletion)
            appState.loadSelectedAccount(from: newAccounts)
        }
    }

    private func initializeAppState() {
        appState.loadSelectedAccount(from: accounts)
    }
}

#Preview {
    ContentView()
        .environment(RecurrenceReminders())
        .environment(AppLock())
        .environment(DataStorageManager.shared)
        .environment(NavigationRouter())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
