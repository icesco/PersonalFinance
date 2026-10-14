import SwiftUI
import SwiftData
import FinanceCore

struct SharedCategoryNotice: View {
    let conto: Conto?
    var body: some View {
        if let conto, conto.usesSharedCategories == true {
            VStack(alignment: .leading, spacing: 6) {
                Label("Le categorie di questo conto sono condivise con le persone invitate.", systemImage: "person.2")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Gestisci categorie condivise") { SharedContoCategoriesView(conto: conto) }
                    .frame(minHeight: 44)
            }
        }
    }
}

struct SharedContoCategoriesView: View {
    let conto: Conto

    var body: some View {
        CategoryListManagementView(sharedConto: conto, isManaging: true)
    }
}

struct SharedCategoriesAccountHeader: View {
    let conto: Conto
    var body: some View {
        HStack(spacing: 14) {
            FormRowIcon(name: "person.2", tint: ForgiaPalette.sageSurface)
            VStack(alignment: .leading, spacing: 3) {
                Text("Conto condiviso").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                Text(conto.name ?? "Conto")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }
}
