//
//  CloudSyncDetailView.swift
//  Personal Finance
//
//  Detailed iCloud sync status page.
//

import SwiftUI
import FinanceCore

struct CloudSyncDetailView: View {
    @Environment(DataStorageManager.self) private var dataStorageManager
    @State private var cloudKitHelper = CloudKitHelper.shared

    var body: some View {
        List {
            statusSection
            storageSection
            actionsSection
            #if DEBUG
            diagnosticSection
            #endif
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloudKitHelper.refreshSyncStatus()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Stato") {
            row(title: "Account iCloud",
                value: cloudKitHelper.isAccountConnected ? "Connesso" : "Non connesso",
                icon: cloudKitHelper.isAccountConnected ? "person.icloud.fill" : "person.icloud",
                color: cloudKitHelper.isAccountConnected ? .green : .orange)

            row(title: "Sincronizzazione",
                value: cloudKitHelper.isSyncing ? "In corso" : "Inattiva",
                icon: cloudKitHelper.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "icloud",
                color: cloudKitHelper.isSyncing ? .blue : .secondary)

            if let date = cloudKitHelper.lastSyncDate {
                row(title: "Ultimo aggiornamento",
                    value: date.formatted(.dateTime.day().month().hour().minute()),
                    icon: "clock",
                    color: .secondary)
            }

            if let error = cloudKitHelper.syncError {
                row(title: "Errore",
                    value: error.localizedDescription,
                    icon: "exclamationmark.triangle",
                    color: .red)
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section("Archiviazione") {
            row(title: "Modalita'",
                value: dataStorageManager.isCloudSyncEnabled ? "iCloud" : "Solo locale",
                icon: dataStorageManager.isCloudSyncEnabled ? "icloud.fill" : "internaldrive",
                color: dataStorageManager.isCloudSyncEnabled ? .blue : .secondary)

            row(title: "Container",
                value: FinanceCoreModule.cloudKitContainerIdentifier,
                icon: "shippingbox",
                color: .secondary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section("Azioni") {
            Button {
                Task {
                    await cloudKitHelper.refreshSyncStatus()
                }
            } label: {
                Label("Aggiorna stato", systemImage: "arrow.clockwise")
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Apri Impostazioni", systemImage: "gear")
            }
        }
    }

    // MARK: - Diagnostic (DEBUG only)

    #if DEBUG
    private var diagnosticSection: some View {
        Section("Diagnostica") {
            row(title: "iCloud disponibile",
                value: cloudKitHelper.isCloudKitAvailable ? "Si'" : "No",
                icon: "checkmark.circle",
                color: cloudKitHelper.isCloudKitAvailable ? .green : .red)

            row(title: "Container attuale",
                value: dataStorageManager.currentContainer != nil ? "Inizializzato" : "Non inizializzato",
                icon: "cylinder",
                color: dataStorageManager.currentContainer != nil ? .green : .orange)

            row(title: "Migrazione in corso",
                value: dataStorageManager.isMigrating ? "Si'" : "No",
                icon: "arrow.left.arrow.right",
                color: dataStorageManager.isMigrating ? .orange : .secondary)
        }
    }
    #endif

    // MARK: - Helpers

    private func row(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}
