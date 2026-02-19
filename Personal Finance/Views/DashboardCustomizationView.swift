//
//  DashboardCustomizationView.swift
//  Personal Finance
//
//  Sheet for reordering and toggling dashboard sections.
//

import SwiftUI

struct DashboardCustomizationView: View {
    @Bindable var layoutManager: DashboardLayoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layoutManager.sections) { config in
                        HStack(spacing: 12) {
                            Image(systemName: config.section.icon)
                                .font(.body)
                                .foregroundStyle(config.isVisible ? Color.accentColor : .secondary)
                                .frame(width: 28)

                            Text(config.section.displayName)
                                .foregroundStyle(config.isVisible ? .primary : .secondary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { config.isVisible },
                                set: { _ in layoutManager.toggleVisibility(for: config.section) }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onMove { source, destination in
                        layoutManager.moveSection(from: source, to: destination)
                    }
                } header: {
                    Text("Trascina per riordinare, attiva o disattiva le sezioni")
                } footer: {
                    Text("Il saldo e le azioni rapide sono sempre visibili in cima alla dashboard.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Personalizza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ripristina") {
                        layoutManager.reset()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    DashboardCustomizationView(layoutManager: DashboardLayoutManager())
}
