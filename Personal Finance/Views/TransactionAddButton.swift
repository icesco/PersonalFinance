import SwiftUI
import FinanceCore

/// Marks a tab's root screen as one where the shared new-transaction button belongs.
/// The button disappears as soon as the root is covered by a pushed screen or `isActive` turns false.
struct TransactionButtonRoot: ViewModifier {
    let tab: AppTab
    var isActive = true
    @Environment(AppStateManager.self) private var appState
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true; update() }
            .onDisappear { isOnScreen = false; update() }
            .onChange(of: isActive) { _, _ in update() }
    }

    private func update() {
        if isOnScreen && isActive {
            appState.transactionButtonRoots.insert(tab)
        } else {
            appState.transactionButtonRoots.remove(tab)
        }
    }
}

extension View {
    func transactionButtonRoot(_ tab: AppTab, isActive: Bool = true) -> some View {
        modifier(TransactionButtonRoot(tab: tab, isActive: isActive))
    }
}

/// The app-wide floating button: tap for a new expense, long-press for income or a transfer.
struct TransactionAddButton: View {
    @Environment(AppStateManager.self) private var appState
    @State private var showingVoice = false

    var body: some View {
        Menu {
            Button("Aggiungi con la voce", systemImage: "mic.fill") { showingVoice = true }
            Divider()
            Button("Nuova spesa", systemImage: "arrow.up.right") {
                appState.presentQuickTransaction(type: .expense)
            }
            Button("Nuova entrata", systemImage: "arrow.down.left") {
                appState.presentQuickTransaction(type: .income)
            }
            if appState.activeConti(for: appState.selectedAccount).count >= 2 {
                Button("Nuovo trasferimento", systemImage: "arrow.left.arrow.right") {
                    appState.presentQuickTransaction(type: .transfer)
                }
            }
        } label: {
            Label("Nuova spesa", systemImage: "square.and.pencil")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.onAccent)
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .glassEffect(.regular.tint(ForgiaPalette.accent).interactive(), in: .capsule)
        } primaryAction: {
            // A tap goes straight to the most common case; long-press offers the other kinds.
            appState.presentQuickTransaction(type: .expense)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transactions-add")
        .accessibilityHint("Tieni premuto per aggiungere con la voce, scegliere entrata o trasferimento")
        .financePresentation(isPresented: $showingVoice, title: "Aggiungi con la voce", width: 600, height: 720) {
            VoiceTransactionView()
        }
    }
}
