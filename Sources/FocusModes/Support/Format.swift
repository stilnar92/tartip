import Foundation

// Formatters are expensive to create, so each format is made once.
enum Fmt {
    static let clock = make("HH:mm")
    static let weekdayClock = make("EEE HH:mm")
    static let dayTitle = make("EEEE · d MMM")
    static let dayKey = make("yyyy-MM-dd")
    static let logStamp = make("yyyy-MM-dd HH:mm:ss")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}

func clockLabel(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

// "45m", "1h", "1h 30m": the one way minutes are shown.
func minutesLabel(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
}

func limitLabel(_ minutes: Int) -> String { minutes == 0 ? "No limit" : minutesLabel(minutes) }

func formatDuration(_ secs: Int) -> String { minutesLabel(secs / 60) }

// "4:05" until `end`.
func countdown(to end: Date, from now: Date) -> String {
    let sec = max(0, Int(end.timeIntervalSince(now)))
    return String(format: "%d:%02d", sec / 60, sec % 60)
}
