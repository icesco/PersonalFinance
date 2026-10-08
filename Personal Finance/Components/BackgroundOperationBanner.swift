//
//  BackgroundOperationBanner.swift
//  Personal Finance
//
//  Floating overlay that shows iCloud sync progress.
//

import SwiftUI
import Observation
import FinanceCore

// MARK: - Manager

@Observable
@MainActor
final class BackgroundOperationManager {
    static let shared = BackgroundOperationManager()

    private(set) var isVisible = false
    private(set) var message = ""
    private(set) var errorDetail: String?
    private(set) var isSuccess: Bool? = nil  // nil = in progress

    private var dismissTask: Task<Void, Never>?

    private init() {
        let center = NotificationCenter.default

        center.addObserver(forName: .containerDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissTask?.cancel()
                self?.isVisible = false
                self?.errorDetail = nil
            }
        }

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
        center.addObserver(forName: .cloudSyncSessionDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSuccess == nil else { return }
                self.dismissTask?.cancel()
                self.isVisible = false
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
        message = "Sincronizzazione iCloud"
        errorDetail = nil
        isSuccess = nil
        isVisible = true
    }

    private func showCompleted() {
        // Fast sessions never announced a banner; keep their completion invisible too.
        guard isVisible, isSuccess == nil else { return }
        message = "iCloud aggiornato"
        errorDetail = nil
        isSuccess = true
        isVisible = true
        scheduleDismiss(after: 2)
    }

    private func showFailed(error: Error?) {
        message = "Sincronizzazione non riuscita"
        errorDetail = error?.localizedDescription
        isSuccess = false
        isVisible = true
        scheduleDismiss(after: 6)
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}

// MARK: - Banner View

struct BackgroundOperationBanner: View {
    @State private var manager = BackgroundOperationManager.shared
    @Environment(DataStorageManager.self) private var storage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var topSpacing: CGFloat {
        #if os(iOS)
        // Keep the toast below navigation titles and toolbar controls, including landscape.
        return verticalSizeClass == .compact ? 40 : 52
        #else
        return 8
        #endif
    }

    private var preview: (message: String, success: Bool?)? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_CLOUD_BANNER_SUCCESS") { return ("iCloud aggiornato", true) }
        if arguments.contains("UITEST_CLOUD_BANNER_ERROR") { return ("Sincronizzazione non riuscita", false) }
        if arguments.contains("UITEST_CLOUD_BANNER") { return ("Sincronizzazione iCloud", nil) }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if preview != nil || (manager.isVisible && storage.isCloudSyncEnabled) {
                CloudSyncBannerContent(message: preview?.message ?? manager.message,
                                       isSuccess: preview.map(\.success) ?? manager.isSuccess)
                    .accessibilityHint(manager.errorDetail ?? "")
                    .padding(.horizontal, 20)
                    .padding(.top, topSpacing)
                    .frame(maxWidth: .infinity)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: manager.isVisible && storage.isCloudSyncEnabled)
    }
}

struct CloudSyncBannerContent: View {
    let message: String
    let isSuccess: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shape: AnyShape {
        dynamicTypeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: 24))
            : AnyShape(Capsule())
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: isSuccess == nil && !reduceMotion)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                if isSuccess == false {
                    Text("Controlla iCloud nelle Impostazioni.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(iconColor.opacity(0.12)), in: shape)
        .frame(maxWidth: 400)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cloud-sync-banner")
    }

    private var symbol: String {
        if isSuccess == nil { return "arrow.trianglehead.2.clockwise.rotate.90.icloud" }
        return isSuccess == true ? "checkmark.icloud" : "exclamationmark.icloud"
    }

    private var iconColor: Color {
        if isSuccess == nil {
            return .accentColor
        } else if isSuccess == true {
            return .green
        } else {
            return .red
        }
    }
}

/// A data-free first frame while SwiftData opens the local store.
struct StartupPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    FormiLogo(size: 36)
                    Text("Formi")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .tracking(-1)
                }
                VStack(alignment: .leading, spacing: 24) {
                    StartupPlaceholderCard(height: 190)
                    StartupPlaceholderCard(height: 150)
                    StartupPlaceholderCard(height: 160)
                }
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.top, 14)
        }
        .scrollDisabled(true)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apertura di Formi")
    }
}

private struct StartupPlaceholderCard: View {
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Il tuo riepilogo")
                .font(.headline)
            Text("Disponibilità del libro")
                .font(.title2)
            Spacer(minLength: 0)
            Text("I tuoi dati")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 24))
    }
}
