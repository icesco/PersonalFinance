import SwiftUI
import SwiftData
import FinanceCore

struct SuggestedCategoriesPicker: View {
    let account: Account
    var sharedConto: Conto? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var error: String?

    private var available: [FinanceCategory.DefaultCategoryDefinition] {
        if let sharedConto { return CategoryDefaults.suggestions(for: sharedConto) }
        return CategoryDefaults.suggestions(for: account)
    }
    private var availableKeys: Set<String> { Set(available.map(\.stableKey)) }
    private var selectedKeys: Set<String> {
        var keys = selected.intersection(availableKeys)
        for definition in available where keys.contains(definition.stableKey) {
            if let parent = definition.parentKey, availableKeys.contains(parent) { keys.insert(parent) }
        }
        return keys
    }
    private var roots: [FinanceCategory.DefaultCategoryDefinition] {
        FinanceCategory.defaultCategoryDefinitions.filter { root in
            root.parentKey == nil && (availableKeys.contains(root.stableKey) || available.contains { $0.parentKey == root.stableKey })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(sharedConto?.name ?? account.name ?? "Libro", systemImage: sharedConto == nil ? "books.vertical" : "person.2")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ForgiaPalette.accent)
                        Text("Scegli le categorie da aggiungere.")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Seleziona una categoria principale per includere tutte le sue sottocategorie, poi togli quelle che non vuoi. Se scegli una sottocategoria da sola, includiamo la principale quando manca.")
                            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                        if sharedConto != nil {
                            Text("Le nuove categorie saranno condivise con le persone invitate a questo conto.")
                                .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }
                    HStack {
                        Text("Da aggiungere: \(selectedKeys.count)").font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("suggested-categories-count")
                        Spacer(minLength: 8)
                        Button(selectedKeys == availableKeys && !availableKeys.isEmpty ? "Deseleziona" : "Seleziona tutte") {
                            selected = selectedKeys == availableKeys ? [] : availableKeys
                        }
                        .font(.subheadline).frame(minHeight: 44)
                        .disabled(availableKeys.isEmpty)
                    }
                    ForEach(roots, id: \.stableKey) { root in
                        FormCard {
                            choiceRow(root, isChild: false)
                            ForEach(available.filter { $0.parentKey == root.stableKey }, id: \.stableKey) { child in
                                FormRowDivider()
                                choiceRow(child, isChild: true)
                            }
                        }
                    }
                    if roots.isEmpty {
                        ContentUnavailableView("Nessuna categoria da aggiungere", systemImage: "checkmark.circle",
                            description: Text("Le categorie suggerite sono già presenti oppure sono state archiviate."))
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(ForgiaPalette.spending) }
                }
                .frame(maxWidth: 560, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }
            .themedBackground()
            .navigationTitle("Scegli categorie")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                FinanceDismissToolbar { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi", action: add).disabled(selectedKeys.isEmpty)
                        .accessibilityIdentifier("suggested-categories-add")
                }
            }
        }
        .tint(ForgiaPalette.accent)
        #if os(iOS)
        .presentationBackground(ForgiaPalette.canvas)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 440, idealWidth: 560, minHeight: 480, idealHeight: 720)
        #endif
    }

    private func choiceRow(_ definition: FinanceCategory.DefaultCategoryDefinition, isChild: Bool) -> some View {
        let isAvailable = availableKeys.contains(definition.stableKey)
        let children = Set(available.filter { $0.parentKey == definition.stableKey }.map(\.stableKey))
        let effectiveSelection = selectedKeys
        let includesRoot = effectiveSelection.contains(definition.stableKey)
        let selectedChildren = children.intersection(effectiveSelection)
        let isSelected = children.isEmpty ? includesRoot : (!isAvailable || includesRoot) && children.isSubset(of: effectiveSelection)
        let isPartial = !isSelected && (includesRoot || !selectedChildren.isEmpty)
        return Button {
            if isSelected {
                selected.remove(definition.stableKey)
                if !isChild {
                    for child in available where child.parentKey == definition.stableKey { selected.remove(child.stableKey) }
                }
            } else {
                if isAvailable { selected.insert(definition.stableKey) }
                if !isChild { selected.formUnion(children) }
            }
        } label: {
            HStack(spacing: 12) {
                if isChild {
                    Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                Image(systemName: definition.icon)
                    .font(.system(size: isChild ? 17 : 20, weight: .medium))
                    .foregroundStyle(Color(hex: definition.color))
                    .frame(width: isChild ? 34 : 40, height: isChild ? 34 : 40)
                    .background(Color(hex: definition.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(definition.name).font(isChild ? .subheadline : .headline).foregroundStyle(.primary)
                    if !isAvailable { Text("Già presente").font(.caption).foregroundStyle(ForgiaPalette.mutedText) }
                }
                Spacer(minLength: 8)
                Image(systemName: isPartial ? "minus.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3).foregroundStyle(isSelected || isPartial ? ForgiaPalette.accent : ForgiaPalette.mutedText)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!isAvailable && children.isEmpty)
        .accessibilityLabel(definition.name)
        .accessibilityValue(isPartial ? "Selezione parziale" : (isSelected ? "Selezionata" : "Non selezionata"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("suggested-category-\(definition.stableKey)")
    }

    private func add() {
        do {
            let defaults = CategoryDefaults(context: context)
            if let sharedConto { try defaults.addSuggestions(selectedKeys, to: sharedConto) }
            else { try defaults.addSuggestions(selectedKeys, to: account) }
            dismiss()
        } catch { self.error = "Categorie non aggiunte. Le tue scelte restano qui: riprova." }
    }
}
