import SwiftUI
import FinanceCore

struct AnalyticsWidgetsPage: View {
    let viewModel: DashboardViewModel
    let theme: AppTheme
    let height: CGFloat

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var periodLabel: String {
        viewModel.selectedPeriod.displayName
    }

    var body: some View {
        VStack(spacing: 10) {
            // Top row: 2 widgets side by side
            LazyVGrid(columns: columns, spacing: 10) {
                BalanceDistributionWidget(
                    income: viewModel.monthlyIncome,
                    expenses: viewModel.monthlyExpenses,
                    periodAvgIncome: viewModel.periodAverageIncome,
                    periodAvgExpenses: viewModel.periodAverageExpenses,
                    periodLabel: periodLabel,
                    theme: theme
                )

                SavingsRateWidget(
                    income: viewModel.monthlyIncome,
                    expenses: viewModel.monthlyExpenses,
                    periodAvgIncome: viewModel.periodAverageIncome,
                    periodAvgExpenses: viewModel.periodAverageExpenses,
                    periodLabel: periodLabel,
                    theme: theme
                )
            }

            // Full width: spending trend
            SpendingTrendWidget(
                currentMonthExpenses: viewModel.monthlyExpenses,
                averageExpenses: viewModel.averageMonthlyExpenses,
                trend: viewModel.monthlyExpensesTrend,
                periodLabel: periodLabel,
                theme: theme
            )
        }
        .frame(height: height, alignment: .top)
    }
}
