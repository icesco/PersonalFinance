import Foundation

/// Time period for dashboard charts
public enum ChartPeriod: String, CaseIterable, Identifiable, Sendable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1A"
    case all = "Tutto"

    public var id: String { rawValue }

    public var monthsCount: Int? {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }

    /// Whether X-axis should show weeks instead of months
    public var useWeeklyAxis: Bool {
        self == .oneMonth
    }

    /// Calendar component for X-axis stride
    public var axisStrideComponent: Calendar.Component {
        useWeeklyAxis ? .weekOfMonth : .month
    }

    /// Number of units between X-axis labels
    public var axisStrideCount: Int {
        switch self {
        case .oneMonth: return 1
        case .threeMonths: return 1
        case .sixMonths: return 1
        case .oneYear: return 2
        case .all: return 3
        }
    }

    public var displayName: String {
        switch self {
        case .oneMonth: return "1 Mese"
        case .threeMonths: return "3 Mesi"
        case .sixMonths: return "6 Mesi"
        case .oneYear: return "1 Anno"
        case .all: return "Tutto"
        }
    }
}
