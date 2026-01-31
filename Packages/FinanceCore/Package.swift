// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinanceCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
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
            path: "Sources/FinanceCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "FinanceCoreTests",
            dependencies: ["FinanceCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]),
    ]
)
