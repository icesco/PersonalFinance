//
//  Personal_FinanceApp.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore
import CloudKit

@main
struct Personal_FinanceApp: App {
    @State private var navigationRouter = NavigationRouter()
    @State private var dataStorageManager = DataStorageManager.shared
    @State private var isInitialized = false
    @State private var initializationError: Error?
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let error = initializationError {
                    ErrorView(error: error) {
                        Task {
                            await initializeApp()
                        }
                    }
                } else if isInitialized, let container = dataStorageManager.currentContainer {
                    ContentView()
                        .environment(navigationRouter)
                        .environment(dataStorageManager)
                        .modelContainer(container)
                } else {
                    LoadingView()
                }
            }
            .task {
                await initializeApp()
            }
        }
    }
    
    // MARK: - App Initialization
    
    @MainActor
    private func initializeApp() async {
        do {
            // Check and perform migration if needed
            if dataStorageManager.needsMigration() {
                try dataStorageManager.performMigration()
            }
            
            // Initialize the container
            try await dataStorageManager.initializeContainer()
            
            isInitialized = true
            initializationError = nil
        } catch {
            print("Failed to initialize app: \(error)")
            initializationError = error
            isInitialized = false
        }
    }
}

// MARK: - Supporting Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Initializing Personal Finance...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Initialization Failed")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
