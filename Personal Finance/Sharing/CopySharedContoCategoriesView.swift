import SwiftUI
import SwiftData
import FinanceCore

struct CopySharedContoCategoriesView: View {
    let conto: Conto
    let onComplete: (Int) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [FinanceCategory]
    @Query private var memberships: [SharedBookMembership]
    @State private var selected: Set<UUID> = []
    @State private var error: String?
    private var categories: [FinanceCategory] {
        SharedContoCategories.personalCategories(in: allCategories, memberships: memberships)
            .sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending }
    }
    private var books: [Account] {
        var seen: Set<UUID> = []
        return categories.compactMap(\.account).filter { seen.insert($0.id).inserted }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
    }
    private var canCopy: Bool {
        !selected.isEmpty && selected.isSubset(of: Set(categories.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SharedCategoriesAccountHeader(conto: conto)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scegli le categorie personali da copiare.")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Le copie saranno condivise con le persone invitate e resteranno indipendenti dalle originali.")
                            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                        DisclosureGroup("Come funziona la copia") {
                            Text("Se scegli una sottocategoria, verrà copiata anche la sua categoria principale. Le copie già presenti non vengono duplicate o sovrascritte.")
                                .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                                .padding(.top, 6)
                        }
                        .font(.subheadline)
                        .tint(ForgiaPalette.accent)
                    }
                    if !selected.isEmpty {
                        Text("Selezionate: \(selected.count)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ForgiaPalette.accent)
                            .accessibilityIdentifier("copy-shared-categories-count")
                    }
                    ForEach(books) { book in
                        let items = categories.filter { $0.account?.id == book.id }
                        FormCard(title: book.name ?? "Libro") {
                            ForEach(items) { category in
                                CopyCategoryRow(category: category, isSelected: selected.contains(category.id)) {
                                    if !selected.insert(category.id).inserted { selected.remove(category.id) }
                                }
                                if category.id != items.last?.id { FormRowDivider() }
                            }
                        }
                    }
                    if categories.isEmpty {
                        Text("Non ci sono categorie personali disponibili. Puoi creare nuove categorie direttamente nell’elenco condiviso.")
                            .foregroundStyle(ForgiaPalette.mutedText).unifiedCard()
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(ForgiaPalette.spending)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .themedBackground()
            .navigationTitle("Copia categorie")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                FinanceDismissToolbar { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copia", action: copy)
                        .disabled(!canCopy)
                        .accessibilityLabel("Copia categorie selezionate")
                        .accessibilityIdentifier("copy-shared-categories-confirm")
                }
            }
        }
        .tint(ForgiaPalette.accent)
        #if os(iOS)
        .presentationBackground(ForgiaPalette.canvas)
        .presentationDragIndicator(.visible)
        #elseif os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
        #endif
    }
    private func copy() {
        let container = context.container
        do {
            let count = try SharedContoCategories.copyPersonalCategories(contoID: conto.id, categoryIDs: selected, container: container)
            onComplete(count)
            dismiss()
        } catch { self.error = "Copia non completata. Controlla che il conto e le categorie siano ancora disponibili, poi riprova." }
    }
}

private struct CopyCategoryRow: View {
    let category: FinanceCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FormRow(icon: category.icon ?? "tag", tint: category.tint.opacity(0.12)) {
                Text(category.displayPath)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                Spacer(minLength: 12)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayPath)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("copy-shared-category-\(category.id)")
    }
}
