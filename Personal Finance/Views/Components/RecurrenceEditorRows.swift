import SwiftUI
import FinanceCore

/// Shared by quick entry, creation and editing so every series has the same controls.
struct RecurrenceEditorRows: View {
    @Binding var isRecurring: Bool
    @Binding var frequency: RecurrenceFrequency
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date
    let startDate: Date
    @State private var showingFrequency = false

    private var validEnd: Date? {
        RecurrenceSchedule.inclusiveEnd(anchor: startDate, lastDay: endDate)
    }

    var body: some View {
        Group {
            FormRow(icon: "arrow.triangle.2.circlepath", tint: ForgiaPalette.sageSurface) {
                Toggle("Transazione ricorrente", isOn: $isRecurring.animation())
                    .tint(ForgiaPalette.accent)
            }
            if isRecurring {
                FormRowDivider()
                Button {
                    showingFrequency = true
                } label: {
                    FormRow(icon: "calendar.badge.clock") {
                        FormSelectionLabel(title: "Cadenza", value: frequency.displayName)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recurrence-frequency")

                FormRowDivider()
                FormRow(icon: "flag.checkered") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Termina")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                        Picker("Termina", selection: $hasEndDate.animation()) {
                            Text("Mai").tag(false)
                            Text("In una data").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("recurrence-end-mode")
                    }
                    .padding(.vertical, 12)
                }
                if hasEndDate {
                    FormRowDivider()
                    FormRow(icon: "calendar.badge.minus") {
                        DatePicker("Ultimo giorno", selection: $endDate,
                                   in: Calendar.current.startOfDay(for: startDate)...,
                                   displayedComponents: .date)
                            .tint(ForgiaPalette.accent)
                            .accessibilityIdentifier("recurrence-end-date")
                    }
                }
                Text(hasEndDate
                     ? (validEnd == nil
                        ? "La fine della ricorrenza non può precedere la data iniziale."
                        : "La ricorrenza include il giorno scelto e poi si interrompe.")
                     : "La ricorrenza continua finché non la interrompi.")
                    .font(.caption)
                    .foregroundStyle(hasEndDate && validEnd == nil ? Color.red : ForgiaPalette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $showingFrequency) {
            NavigationStack {
                List {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { option in
                        Button {
                            frequency = option
                            showingFrequency = false
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if frequency == option {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(ForgiaPalette.accent)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recurrence-frequency-\(option.rawValue)")
                        .accessibilityAddTraits(frequency == option ? .isSelected : [])
                    }
                }
                .navigationTitle("Cadenza")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { showingFrequency = false }
                    }
                }
            }
            .tint(ForgiaPalette.accent)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
