//
//  SettingsView.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import CloudKit
import FinanceCore

struct SettingsView: View {
    @Environment(DataStorageManager.self) private var dataStorageManager
    @State private var cloudKitStatus: CKAccountStatus = .couldNotDetermine
    @State private var isCheckingCloudKit = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    cloudSyncSection
                } header: {
                    Text("Data Synchronization")
                } footer: {
                    Text(cloudSyncFooterText)
                }
                
                Section {
                    storageInfoSection
                } header: {
                    Text("Storage Information")
                }
            }
            .navigationTitle("Settings")
            .task {
                await checkCloudKitStatus()
            }
        }
    }
    
    // MARK: - Cloud Sync Section
    
    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "icloud")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sync")
                        .font(.headline)
                    
                    Text(cloudKitStatusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isCheckingCloudKit {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { dataStorageManager.isCloudSyncEnabled },
                        set: { newValue in
                            if cloudKitStatus == .available {
                                dataStorageManager.isCloudSyncEnabled = newValue
                            }
                        }
                    ))
                    .disabled(cloudKitStatus != .available)
                }
            }
            
            if cloudKitStatus != .available && dataStorageManager.isCloudSyncEnabled {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("iCloud sync is enabled but iCloud account is not available")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Storage Info Section
    
    private var storageInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage Location")
                        .font(.headline)
                    Text(dataStorageManager.isCloudSyncEnabled ? "iCloud" : "Local Device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: dataStorageManager.isCloudSyncEnabled ? "icloud.fill" : "internaldrive")
                    .foregroundColor(dataStorageManager.isCloudSyncEnabled ? .blue : .gray)
            }
            
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Group")
                        .font(.headline)
                    Text("group.personalfinance.shared")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Computed Properties
    
    private var cloudKitStatusDescription: String {
        switch cloudKitStatus {
        case .available:
            return "iCloud account is available"
        case .noAccount:
            return "No iCloud account signed in"
        case .restricted:
            return "iCloud account is restricted"
        case .couldNotDetermine:
            return "Checking iCloud status..."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        @unknown default:
            return "Unknown iCloud status"
        }
    }
    
    private var cloudSyncFooterText: String {
        if dataStorageManager.isCloudSyncEnabled {
            return "Your financial data will be synchronized across all your devices using iCloud."
        } else {
            return "Your financial data will be stored locally on this device only."
        }
    }
    
    // MARK: - CloudKit Status Check
    
    private func checkCloudKitStatus() async {
        isCheckingCloudKit = true
        cloudKitStatus = await dataStorageManager.cloudKitAccountStatus()
        isCheckingCloudKit = false
    }
}

#Preview {
    SettingsView()
        .environment(DataStorageManager.shared)
}