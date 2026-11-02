public import Foundation

public enum Formatting {
    /// X-style compact counts: 942, 9.2K, 12K, 1.3M.
    public static func compact(_ value: Int) -> String {
        let absolute = abs(value)
        func trimmed(_ number: Double, _ suffix: String) -> String {
            let rounded = (number * 10).rounded(.down) / 10
            let text = rounded >= 10 || rounded == rounded.rounded()
                ? String(Int(rounded))
                : String(format: "%.1f", rounded)
            return text + suffix
        }
        switch absolute {
        case ..<1_000: return String(value)
        case ..<1_000_000: return (value < 0 ? "-" : "") + trimmed(Double(absolute) / 1_000, "K")
        case ..<1_000_000_000: return (value < 0 ? "-" : "") + trimmed(Double(absolute) / 1_000_000, "M")
        default: return (value < 0 ? "-" : "") + trimmed(Double(absolute) / 1_000_000_000, "B")
        }
    }

    /// X-style relative timestamps: "now", "42s", "5m", "3h", "Oct 4", "Oct 4, 2024".
    public static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<5: return String(localized: "now")
        case ..<60: return "\(seconds)s"
        case ..<3_600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3_600)h"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
        }
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
