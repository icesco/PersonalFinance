import SwiftUI

struct FinancePeriodHeader: View {
    @Binding var anchor: Date
    @Binding var timeframe: TransactionTimeframe
    var compact = false
    var accessibilityIdentifier = "finance-period-menu"

    private var isAtCurrentPeriod: Bool { timeframe.interval(containing: anchor).end > Date() }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                if !compact {
                Button {
                    anchor = timeframe.moving(anchor, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 44, height: 44)
                    .accessibilityLabel("Periodo precedente")
                }

                Spacer()

                Menu {
                    if compact {
                        Button("Periodo precedente", systemImage: "chevron.left") {
                            anchor = timeframe.moving(anchor, by: -1)
                        }
                        Button("Periodo successivo", systemImage: "chevron.right") {
                            anchor = timeframe.moving(anchor, by: 1)
                        }.disabled(isAtCurrentPeriod)
                        Divider()
                    }
                    Picker("Granularità", selection: $timeframe) {
                        ForEach(TransactionTimeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.displayName).tag(timeframe)
                        }
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(timeframe.title(containing: anchor))
                                .font(.system(.title3, design: .serif, weight: .bold))
                            .foregroundStyle(ForgiaPalette.accent)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.accent)
                        }
                        if let subtitle = timeframe.subtitle(containing: anchor) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.frame(minHeight: 44)
                }
                .accessibilityIdentifier(accessibilityIdentifier)

                Spacer()

                if !compact {
                Button {
                    anchor = timeframe.moving(anchor, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 44, height: 44)
                .disabled(isAtCurrentPeriod)
                .opacity(isAtCurrentPeriod ? 0.4 : 1)
                .accessibilityLabel("Periodo successivo")
                }

            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
