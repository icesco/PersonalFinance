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
    var allowsNone = false
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let hierarchy = CategoryHierarchy(categories: categories, kind: CategoryKind(type))
        #if os(macOS)
        MacCategorySelection(categories: categories, type: type, selection: $selection, allowsNone: allowsNone)
        #else
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
        #endif
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

#if os(macOS)
private struct MacCategorySelection: View {
    @FocusState private var sidebarFocused: Bool
    let categories: [FinanceCategory]
    let type: TransactionType
    @Binding var selection: FinanceCategory?
    let allowsNone: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var rootID: UUID?

    private var hierarchy: CategoryHierarchy {
        CategoryHierarchy(categories: categories, kind: CategoryKind(type))
    }
    private var roots: [FinanceCategory] {
        hierarchy.roots.filter { root in
            search.isEmpty || matches(root) || hierarchy.children(of: root).contains(where: matches)
        }
    }
    private var currentRoot: FinanceCategory? {
        roots.first { $0.id == rootID } ?? roots.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scegli una categoria").font(.headline)
                Spacer()
                TextField("Cerca una categoria", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(16)
            Divider()
            HStack(spacing: 0) {
                List {
                    ForEach(roots, id: \.id) { root in
                        MacThemedSidebarRow(title: root.name ?? "Categoria", symbol: root.icon ?? "tag",
                                            isSelected: currentRoot?.id == root.id) {
                            rootID = root.id
                            sidebarFocused = true
                        }
                    }
                }
                .listStyle(.sidebar)
                .focusable()
                .focusEffectDisabled()
                .focused($sidebarFocused)
                .onMoveCommand { direction in
                    guard let index = roots.firstIndex(where: { $0.id == currentRoot?.id }) else { return }
                    if direction == .up, index > 0 { rootID = roots[index - 1].id }
                    if direction == .down, index + 1 < roots.count { rootID = roots[index + 1].id }
                }
                .frame(width: 205)
                Divider()
                if let root = currentRoot {
                    List {
                        Section(root.name ?? "Categoria") {
                            categoryButton(root)
                        }
                        let children = hierarchy.children(of: root).filter {
                            search.isEmpty || matches(root) || matches($0)
                        }
                        if !children.isEmpty {
                            Section("Sottocategorie") {
                                ForEach(children, id: \.id) { categoryButton($0) }
                            }
                        }
                    }
                    .listStyle(.inset)
                } else {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity)
                }
            }
            Divider()
            HStack {
                Text("Scegli la categoria principale o una sottocategoria.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if allowsNone {
                    Button("Nessuna") { selection = nil; dismiss() }
                }
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 600, height: 460)
        .onAppear {
            rootID = hierarchy.roots.first { root in
                root.id == selection?.id || hierarchy.children(of: root).contains { $0.id == selection?.id }
            }?.id ?? hierarchy.roots.first?.id
        }
        .onChange(of: search) { _, _ in
            if !roots.contains(where: { $0.id == rootID }) { rootID = roots.first?.id }
        }
    }

    private func matches(_ category: FinanceCategory) -> Bool {
        (category.name ?? "").localizedStandardContains(search)
    }

    private func categoryButton(_ category: FinanceCategory) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.icon ?? "tag")
                    .foregroundStyle(category.tint)
                    .frame(width: 24)
                Text(category.name ?? "Categoria")
                Spacer()
                if selection?.id == category.id {
                    Image(systemName: "checkmark").foregroundStyle(category.tint)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayPath)
        .accessibilityAddTraits(selection?.id == category.id ? .isSelected : [])
    }
}
#endif
