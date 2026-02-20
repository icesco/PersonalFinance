//
//  BackgroundOperationBanner.swift
//  Personal Finance
//
//  Floating overlay that shows iCloud sync progress.
//

import SwiftUI
import Observation

// MARK: - Manager

@Observable
@MainActor
final class BackgroundOperationManager {
    static let shared = BackgroundOperationManager()

    private(set) var isVisible = false
    private(set) var message = ""
    private(set) var isSuccess: Bool? = nil  // nil = in progress

    private var dismissTask: Task<Void, Never>?

    private init() {
        let center = NotificationCenter.default

        center.addObserver(forName: .cloudSyncDidBegin, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showSyncing()
            }
        }
        center.addObserver(forName: .cloudSyncDidComplete, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showCompleted()
            }
        }
        center.addObserver(forName: .cloudSyncDidFail, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                let error = notification.userInfo?["error"] as? Error
                self?.showFailed(error: error)
            }
        }
    }

    private func showSyncing() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            message = "Sincronizzazione iCloud..."
            isSuccess = nil
            isVisible = true
        }
    }

    private func showCompleted() {
        withAnimation(.easeInOut(duration: 0.3)) {
            message = "Sincronizzazione completata"
            isSuccess = true
        }
        scheduleDismiss(after: 2)
    }

    private func showFailed(error: Error?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            message = error?.localizedDescription ?? "Errore di sincronizzazione"
            isSuccess = false
        }
        scheduleDismiss(after: 4)
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                isVisible = false
            }
        }
    }
}

// MARK: - Banner View

struct BackgroundOperationBanner: View {
    @State private var manager = BackgroundOperationManager.shared

    var body: some View {
        if manager.isVisible {
            HStack(spacing: 10) {
                Group {
                    if manager.isSuccess == nil {
                        Image(systemName: "icloud")
                            .symbolEffect(.pulse)
                    } else if manager.isSuccess == true {
                        Image(systemName: "checkmark.icloud")
                    } else {
                        Image(systemName: "exclamationmark.icloud")
                    }
                }
                .font(.body)
                .foregroundStyle(iconColor)

                Text(manager.message)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var iconColor: Color {
        if manager.isSuccess == nil {
            return .accentColor
        } else if manager.isSuccess == true {
            return .green
        } else {
            return .red
        }
    }
}
