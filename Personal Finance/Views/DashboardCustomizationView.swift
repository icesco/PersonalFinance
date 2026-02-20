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

    @State private var selectedPreset: UserExperienceLevel?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Preset Section
                Section {
                    HStack(spacing: 10) {
                        ForEach(UserExperienceLevel.allCases) { level in
                            presetButton(for: level)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Preset")
                } footer: {
                    Text("Scegli un preset per configurare rapidamente i widget, poi personalizza liberamente.")
                }

                // MARK: - Sections List
                Section {
                    ForEach(layoutManager.sections) { config in
                        HStack(spacing: 12) {
                            Image(systemName: config.section.icon)
                                .font(.body)
                                .foregroundStyle(config.isVisible ? Color.accentColor : .secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(config.section.displayName)
                                        .foregroundStyle(config.isVisible ? .primary : .secondary)
                                    levelBadge(for: config.section.minimumLevel)
                                }
                                Text(config.section.helpText)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { config.isVisible },
                                set: { _ in
                                    selectedPreset = nil
                                    layoutManager.toggleVisibility(for: config.section)
                                }
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
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Personalizza")
            .toolbarTitleDisplayMode(.inline)
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ripristina") {
                        selectedPreset = nil
                        layoutManager.reset()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Preset Button

    private func presetButton(for level: UserExperienceLevel) -> some View {
        let isSelected = selectedPreset == level
        let widgetCount = DashboardSection.allCases.filter { section in
            let order: [UserExperienceLevel] = [.beginner, .standard, .advanced]
            let sectionIdx = order.firstIndex(of: section.minimumLevel) ?? 0
            let levelIdx = order.firstIndex(of: level) ?? 0
            return sectionIdx <= levelIdx
        }.count

        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedPreset = level
                layoutManager.applyPreset(for: level)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: level.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : level.iconColor)

                Text(level.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text("\(widgetCount) widget")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? level.iconColor : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Level Badge

    private func levelBadge(for level: UserExperienceLevel) -> some View {
        Text(level.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(level.iconColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(level.iconColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

#Preview {
    DashboardCustomizationView(layoutManager: DashboardLayoutManager())
}
