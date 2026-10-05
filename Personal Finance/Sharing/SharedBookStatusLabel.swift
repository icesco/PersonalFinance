import SwiftUI
import FinanceCore

struct SharedBookStatusLabel: View {
    let status: SharedBookAutomaticRefresh.Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Condivisione del libro", systemImage: "person.2")
            switch status {
            case .needsReview:
                Label("Differenze da verificare", systemImage: "exclamationmark.bubble")
                    .font(.caption).foregroundStyle(.orange)
            case .failed:
                Label("Aggiornamento non riuscito", systemImage: "exclamationmark.icloud")
                    .font(.caption).foregroundStyle(.orange)
            case .updated, nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct SharedBookStatusFixture: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Libro con differenze") { SharedBookStatusLabel(status: .needsReview) }
                Section("Libro non aggiornato") { SharedBookStatusLabel(status: .failed) }
                Section("Libro aggiornato") { SharedBookStatusLabel(status: .updated(Date())) }
            }
            .navigationTitle("Pianifica")
        }
    }
}
#endif
