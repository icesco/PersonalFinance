// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinanceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FinanceCore",
            targets: ["FinanceCore"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "FinanceCore",
            dependencies: [],
            sources: [
                "FinanceCore.swift",
                "Models/Account.swift",
                "Models/AccountStatistics.swift",
                "Models/Budget.swift", 
                "Models/BudgetCategory.swift",
                "Models/Category.swift",
                "Models/Conto.swift",
                "Models/Transaction.swift",
                "Models/SavingsGoal.swift",
                "Analysis/FinancialAnalysis.swift",
                "Services/DataIntegrityService.swift",
                "Services/StatisticsService.swift"
            ]),
        .testTarget(
            name: "FinanceCoreTests",
            dependencies: ["FinanceCore"]),
    ]
)
