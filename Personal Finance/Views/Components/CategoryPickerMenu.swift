import SwiftUI
import FinanceCore

/// Picks a macro category or one of its subcategories, limited to those that fit the transaction type.
/// Choosing the macro category itself is the quick option when the detail is uncertain.
struct CategoryPickerMenu<MenuLabel: View>: View {
    let categories: [FinanceCategory]
    let type: TransactionType
    @Binding var selection: FinanceCategory?
    var noneTitle = "Nessuna categoria"
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        let hierarchy = CategoryHierarchy(categories: categories, kind: CategoryKind(type))
        Menu {
            Section {
                option(nil, title: noneTitle, icon: "tag.slash")
            }
            Section {
                ForEach(hierarchy.roots, id: \.id) { root in
                    let children = hierarchy.children(of: root)
                    if children.isEmpty {
                        option(root, title: root.name ?? "Categoria", icon: root.icon)
                    } else {
                        Menu {
                            option(root, title: "\(root.name ?? "Categoria") in generale", icon: root.icon)
                            Section("Più nel dettaglio") {
                                ForEach(children, id: \.id) { option($0, title: $0.name ?? "Categoria", icon: $0.icon) }
                            }
                        } label: {
                            Label(root.name ?? "Categoria",
                                  systemImage: contains(selection, root, children) ? "checkmark" : root.icon ?? "tag")
                        }
                    }
                }
            }
        } label: {
            label()
        }
    }

    private func option(_ category: FinanceCategory?, title: String, icon: String?) -> some View {
        Button {
            selection = category
        } label: {
            Label(title, systemImage: selection?.id == category?.id ? "checkmark" : icon ?? "tag")
        }
    }

    private func contains(_ selection: FinanceCategory?, _ root: FinanceCategory, _ children: [FinanceCategory]) -> Bool {
        guard let selection else { return false }
        return selection.id == root.id || children.contains { $0.id == selection.id }
    }
}

/// Full-screen list for choosing a category: each macro category heads its family,
/// with its subcategories hanging beneath it. Searching also matches the macro category name.
struct CategoryPickerSheet: View {
    let categories: [FinanceCategory]
    let type: TransactionType
    @Binding var selection: FinanceCategory?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let hierarchy = CategoryHierarchy(categories: categories, kind: CategoryKind(type))
        NavigationStack {
            List {
                Section {
                    Text("Scegli la categoria principale se non vuoi entrare nel dettaglio, oppure una sua sottocategoria.")
                        .font(.footnote)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                ForEach(hierarchy.roots, id: \.id) { root in
                    let all = hierarchy.children(of: root)
                    let children = visibleChildren(all, root: root)
                    if searchText.isEmpty || matches(root) || !children.isEmpty {
                        Section {
                            row(root) {
                                CategoryTreeRow(category: root, level: .macro(childCount: all.count),
                                                subtitle: all.isEmpty ? nil : "Tutta la categoria") { check(root) }
                            }
                            .categoryTreeRowStyle(isMacro: true)
                            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                                row(child) {
                                    CategoryTreeRow(category: child, level: .child(isLast: index == children.count - 1)) { check(child) }
                                }
                                .categoryTreeRowStyle(isMacro: false)
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listSectionSpacing(12)
            #endif
            .searchable(text: $searchText, prompt: "Cerca una categoria")
            .navigationTitle("Scegli una categoria")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func matches(_ category: FinanceCategory) -> Bool {
        (category.name ?? "").localizedStandardContains(searchText)
    }

    private func visibleChildren(_ children: [FinanceCategory], root: FinanceCategory) -> [FinanceCategory] {
        guard !searchText.isEmpty, !matches(root) else { return children }
        return children.filter(matches)
    }

    private func row(_ category: FinanceCategory, @ViewBuilder label: () -> some View) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayPath)
        .accessibilityAddTraits(selection?.id == category.id ? .isSelected : [])
    }

    @ViewBuilder
    private func check(_ category: FinanceCategory) -> some View {
        if selection?.id == category.id {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(category.tint)
        }
    }
}
