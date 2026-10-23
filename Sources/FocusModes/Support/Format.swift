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

func limitLabel(_ minutes: Int) -> String {
    if minutes == 0 { return "No limit" }
    return minutes % 60 == 0 ? "\(minutes / 60)h" : (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
}

func formatDuration(_ secs: Int) -> String {
    let m = secs / 60
    if m < 60 { return "\(m)m" }
    return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
}

// "4:05" until `end`.
func countdown(to end: Date, from now: Date) -> String {
    let sec = max(0, Int(end.timeIntervalSince(now)))
    return String(format: "%d:%02d", sec / 60, sec % 60)
}
