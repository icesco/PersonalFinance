import SwiftUI
import FinanceCore

struct CompactTransactionRow: View {
    let transaction: FinanceTransaction
    let currency: String
    var showConto = true
    var showDate = true
    var showsDisclosure = false
    var showsFuture = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isIncome: Bool { transaction.type == .income }
    private var isTransfer: Bool { transaction.type == .transfer }
    private var title: String {
        if let description = transaction.transactionDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return description }
        return transaction.category?.name ?? "Transazione"
    }
    private var subtitle: String {
        var parts: [String] = []
        if showDate {
            parts.append(transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))
        }
        if showConto, let name = transaction.fromConto?.name ?? transaction.toConto?.name { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.icon ?? (isTransfer ? "arrow.left.arrow.right" : isIncome ? "arrow.down.left" : "arrow.up.right"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(isIncome ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                .frame(width: 34, height: 34)
                .background(isIncome ? ForgiaPalette.sageSurface : ForgiaPalette.canvas, in: Circle())
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    details
                    amount
                }
            } else {
                details
                Spacer(minLength: 8)
                amount
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    private var amount: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text((isTransfer ? "" : isIncome ? "+" : "−") + (transaction.amount ?? 0).formatted(.currency(code: currency)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? ForgiaPalette.accent : Color.primary)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            if showsFuture, transaction.date > Date() {
                Text("Futura").font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
            } else if transaction.isRecurring == true {
                Label(transaction.recurrenceFrequency?.displayName ?? "", systemImage: "repeat")
                    .font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
    }
}
