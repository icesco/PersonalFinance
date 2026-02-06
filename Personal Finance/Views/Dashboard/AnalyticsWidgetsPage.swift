import SwiftUI
import FinanceCore

enum WidgetDetailType: String, Identifiable {
    case distribution
    case savingsRate
    case spendingTrend

    var id: String { rawValue }
}

struct AnalyticsWidgetsPage: View {
    let viewModel: DashboardViewModel
    let theme: AppTheme
    let height: CGFloat

    @State private var activeDetail: WidgetDetailType?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var periodLabel: String {
        viewModel.selectedPeriod.displayName
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                // Top row: 2 widgets side by side
                LazyVGrid(columns: columns, spacing: 10) {
                    BalanceDistributionWidget(
                        income: viewModel.monthlyIncome,
                        expenses: viewModel.monthlyExpenses,
                        periodAvgIncome: viewModel.periodAverageIncome,
                        periodAvgExpenses: viewModel.periodAverageExpenses,
                        periodLabel: periodLabel,
                        theme: theme,
                        onTap: { activeDetail = .distribution }
                    )

                    SavingsRateWidget(
                        income: viewModel.monthlyIncome,
                        expenses: viewModel.monthlyExpenses,
                        periodAvgIncome: viewModel.periodAverageIncome,
                        periodAvgExpenses: viewModel.periodAverageExpenses,
                        periodLabel: periodLabel,
                        theme: theme,
                        onTap: { activeDetail = .savingsRate }
                    )
                }

                // Full width: spending trend
                SpendingTrendWidget(
                    currentMonthExpenses: viewModel.monthlyExpenses,
                    averageExpenses: viewModel.averageMonthlyExpenses,
                    trend: viewModel.monthlyExpensesTrend,
                    periodLabel: periodLabel,
                    theme: theme,
                    onTap: { activeDetail = .spendingTrend }
                )
            }
        }
        .frame(height: height, alignment: .top)
        .sheet(item: $activeDetail) { detail in
            NavigationStack {
                switch detail {
                case .distribution:
                    DistributionDetailView(viewModel: viewModel, theme: theme)
                case .savingsRate:
                    SavingsRateDetailView(viewModel: viewModel, theme: theme)
                case .spendingTrend:
                    SpendingTrendDetailView(viewModel: viewModel, theme: theme)
                }
            }
        }
    }
}
