// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FinanceUICalendar",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FinanceUICalendar", targets: ["FinanceUICalendar"]),
    ],
    targets: [
        .target(name: "FinanceUICalendar"),
        .testTarget(
            name: "FinanceUICalendarTests",
            dependencies: ["FinanceUICalendar"]
        ),
    ]
)
