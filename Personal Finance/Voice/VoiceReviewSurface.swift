import SwiftUI
import FinanceCore

struct VoiceReviewSurface: View {
    @Binding var drafts: [VoiceTransactionDraft]
    @Binding var confirmed: Bool
    let text: String
    let conti: [Conto]
    let canSave: Bool
    let addedCount: Int
    let issue: (VoiceTransactionDraft) -> String?
    let onSave: () -> Void
    let onApprove: (UUID) -> Void
    let onEditText: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rivedi movimenti").font(.title2.weight(.semibold))
                    Text(drafts.count == 1 ? "1 movimento da rivedere" : "\(drafts.count) movimenti da rivedere")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .frame(width: 52, height: 52)
                        .background(ForgiaPalette.surface, in: Circle())
                        .overlay { Circle().strokeBorder(ForgiaPalette.border) }
                }
                .buttonStyle(.plain).accessibilityLabel("Chiudi revisione")
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 16)
            List {
                Group {
                    if addedCount > 0 {
                        Label(addedCount == 1 ? "1 movimento aggiunto" : "\(addedCount) movimenti aggiunti", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(ForgiaPalette.accent)
                            .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 8, trailing: 22))
                    }
                    ForEach($drafts) { $draft in
                        let id = draft.id
                        VoiceReviewCard(draft: $draft, conti: conti, issue: issue(draft),
                                        onApprove: { onApprove(id) }, onRemove: { remove(id) })
                            .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(id) } label: {
                                    Label("Rimuovi", systemImage: "trash")
                                }
                                .tint(ForgiaPalette.deficit)
                                .accessibilityIdentifier("voice-swipe-remove-\(id)")
                            }
                            .accessibilityIdentifier("voice-draft-\(id)")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        DisclosureGroup {
                            Text(text).font(.body).textSelection(.enabled)
                                .padding(.top, 8)
                        } label: {
                            Label("Testo dettato", systemImage: "waveform")
                                .font(.body.weight(.medium)).frame(minHeight: 44)
                        }
                        if addedCount == 0 {
                            Button(action: onEditText) {
                                Label("Modifica testo", systemImage: "keyboard")
                            }
                            .buttonStyle(VoiceSecondaryButtonStyle())
                        } else {
                            Text("Per correggere i movimenti rimasti, usa Modifica nelle rispettive schede.")
                                .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }
                    .padding(18).background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                    .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 16, trailing: 22))
                    if drafts.contains(where: { $0.date > Date() }) {
                        Label("I movimenti con una data futura saranno pianificati, senza modificare il saldo attuale.", systemImage: "calendar")
                            .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                            .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 16, trailing: 22))
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if drafts.count > 1 {
                VStack(spacing: 12) {
                    Toggle(isOn: $confirmed) {
                        Text("Ho controllato i movimenti rimasti").font(.subheadline.weight(.medium))
                    }
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("voice-confirm-list")
                    Button(action: onSave) {
                        Label("Aggiungi tutti (\(drafts.count))", systemImage: "checkmark")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 56)
                    }
                    .buttonStyle(VoicePrimaryButtonStyle(cornerRadius: 18))
                    .disabled(!canSave).accessibilityIdentifier("voice-approve")
                }
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 12)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .background(ForgiaPalette.canvas)
                .overlay(alignment: .top) { ForgiaPalette.border.frame(height: 1) }
            }
        }
        .background(ForgiaPalette.canvas.ignoresSafeArea())
        .tint(ForgiaPalette.accent)
    }

    private func remove(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            drafts.removeAll { $0.id == id }
        }
    }
}

private struct VoiceReviewCard: View {
    @Binding var draft: VoiceTransactionDraft
    let conti: [Conto]
    let issue: String?
    let onApprove: () -> Void
    let onRemove: () -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var conto: Conto? { conti.first { $0.id == draft.contoID } }
    private var categories: [FinanceCore.Category] {
        (conto?.account?.categories ?? []).filter { $0.isActive == true && draft.type.map($0.fits) == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    private var category: FinanceCore.Category? { categories.first { $0.id == draft.categoryID } }
    private var currency: String { draft.currency.isEmpty ? (conto?.account?.currency ?? "") : draft.currency }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    title
                    Spacer(minLength: 8)
                    amount
                }
                VStack(alignment: .leading, spacing: 10) { title; amount }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(draft.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                } icon: { Image(systemName: "calendar") }
                Label(conto?.name ?? "Conto da scegliere", systemImage: "creditcard")
                Label(category?.name ?? "Senza categoria", systemImage: category?.icon ?? "tag")
            }
            .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            if let issue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.spending)
            }
            if expanded {
                VoiceReviewEditor(draft: $draft, conti: conti, categories: categories)
                    .transition(.opacity)
            }
            Button(action: onApprove) {
                Label(draft.date > Date() ? "Pianifica movimento" : "Aggiungi movimento", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 52)
            }
            .buttonStyle(VoicePrimaryButtonStyle(cornerRadius: 16))
            .disabled(issue != nil)
            .accessibilityIdentifier("voice-approve-\(draft.id)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { editButton; removeButton }
                    .fixedSize(horizontal: true, vertical: true)
                VStack(spacing: 10) { editButton; removeButton }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ForgiaPalette.border) }
        .labelStyle(.titleAndIcon)
        .onChange(of: draft.contoID) { _, _ in suggestCategory() }
        .onChange(of: draft.type) { _, _ in suggestCategory() }
        .onChange(of: issue, initial: true) { _, issue in if issue != nil { expanded = true } }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(draft.note.isEmpty ? String(localized: "Movimento") : draft.note)
                .font(.headline).lineLimit(2)
            Label(draft.type == .income ? "Entrata" : (draft.type == .expense ? "Spesa" : "Tipo da scegliere"),
                  systemImage: draft.type == .income ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(draft.type == .expense ? ForgiaPalette.spending : ForgiaPalette.accent)
        }
    }

    @ViewBuilder private var amount: some View {
        if let value = CaptureTextParser.decimal(draft.amount), !currency.isEmpty {
            Text(value, format: .currency(code: currency))
                .font(.title2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(ForgiaPalette.accent).fixedSize()
                .contentTransition(reduceMotion ? .identity : .numericText())
        } else {
            Text(draft.amount.isEmpty ? String(localized: "Importo da inserire") : draft.amount)
                .font(.title2.weight(.semibold)).foregroundStyle(ForgiaPalette.accent)
        }
    }

    private var editButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { expanded.toggle() }
        } label: {
            Label(expanded ? "Chiudi dettagli" : "Modifica", systemImage: expanded ? "chevron.up" : "slider.horizontal.3")
                .contentTransition(reduceMotion ? .identity : .opacity)
        }
        .buttonStyle(VoiceSecondaryButtonStyle())
        .accessibilityIdentifier("voice-edit-\(draft.id)")
    }

    private var removeButton: some View {
        Button(role: .destructive, action: onRemove) {
            Label("Rimuovi", systemImage: "trash")
                .font(.subheadline.weight(.medium)).foregroundStyle(ForgiaPalette.deficit)
                .padding(.horizontal, 12).frame(minHeight: 50)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func suggestCategory() {
        let matches = categories.filter {
            !draft.suggestedCategory.isEmpty && ($0.name ?? "").compare(draft.suggestedCategory,
                options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        draft.categoryID = matches.count == 1 ? matches[0].id : nil
    }
}

private struct VoiceReviewEditor: View {
    @Binding var draft: VoiceTransactionDraft
    let conti: [Conto]
    let categories: [FinanceCore.Category]

    var body: some View {
        FormCard {
            FormRow(icon: "text.alignleft") {
                TextField("Descrizione", text: $draft.note, axis: .vertical).lineLimit(1...3)
                    .accessibilityLabel("Descrizione")
            }
            FormRowDivider()
            FormRow(icon: "eurosign") {
                TextField("Importo", text: $draft.amount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.title2.weight(.semibold)).accessibilityLabel("Importo")
                TextField("Valuta", text: $draft.currency).frame(width: 65)
                    .accessibilityLabel("Valuta")
                    .onChange(of: draft.currency) { _, value in draft.currency = value.uppercased().trimmingCharacters(in: .whitespaces) }
            }
            FormRowDivider()
            FormRow(icon: "arrow.up.arrow.down", tint: ForgiaPalette.apricotSurface) {
                Text("Tipo").font(.subheadline)
                Spacer(minLength: 8)
                Picker("Tipo", selection: $draft.type) {
                    Text("Scegli il tipo").tag(nil as TransactionType?)
                    Text("Spesa").tag(Optional(TransactionType.expense))
                    Text("Entrata").tag(Optional(TransactionType.income))
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
            }
            FormRowDivider()
            FormRow(icon: "calendar") {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("Data", selection: $draft.date, displayedComponents: .date)
                        .frame(minHeight: 48)
                    DatePicker("Ora", selection: $draft.date, displayedComponents: .hourAndMinute)
                        .frame(minHeight: 48)
                    if draft.dateNeedsReview {
                        Toggle("Confermo la data", isOn: Binding(get: { !draft.dateNeedsReview }, set: { draft.dateNeedsReview = !$0 }))
                            .padding(.bottom, 10)
                    }
                }
                .onChange(of: draft.date) { _, _ in draft.dateNeedsReview = false }
            }
            FormRowDivider()
            FormRow(icon: "creditcard", tint: ForgiaPalette.sageSurface) {
                Text("Conto").font(.subheadline)
                Spacer(minLength: 8)
                Picker("Conto", selection: $draft.contoID) {
                    Text("Scegli un conto").tag(nil as UUID?)
                    ForEach(conti) { Text($0.name ?? "Conto").tag(Optional($0.id)) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
            }
            FormRowDivider()
            FormRow(icon: "tag", tint: ForgiaPalette.apricotSurface) {
                Text("Categoria").font(.subheadline)
                Spacer(minLength: 8)
                Picker("Categoria", selection: $draft.categoryID) {
                    Text("Senza categoria").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name ?? "Categoria").tag(Optional($0.id)) }
                }.disabled(draft.contoID == nil)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
            }
        }
    }
}
