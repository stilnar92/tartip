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

// Weekdays in the order they're shown (Monday first), with Calendar's numbers (1 = Sunday).
let weekOrder = [2, 3, 4, 5, 6, 7, 1]
let weekdayShort = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]

// "Every day", "Weekdays", "Weekends", "Mon–Thu", "Mon, Wed, Fri".
func daysLabel(_ days: [Int]) -> String {
    let set = Set(days)
    if set.isEmpty || set.count == 7 { return "Every day" }
    if set == [2, 3, 4, 5, 6] { return "Weekdays" }
    if set == [1, 7] { return "Weekends" }
    let ordered = weekOrder.filter(set.contains)
    // A run of 3+ days in a row reads better as a range.
    if ordered.count >= 3, let first = weekOrder.firstIndex(of: ordered[0]),
       weekOrder[first..<min(first + ordered.count, 7)].elementsEqual(ordered) {
        return "\(weekdayShort[ordered.first!]!)–\(weekdayShort[ordered.last!]!)"
    }
    return ordered.compactMap { weekdayShort[$0] }.joined(separator: ", ")
}

// "a, b and c" in English: the UI isn't localized, so the system language mustn't leak in.
func andList(_ l: [String]) -> String {
    l.count < 2 ? l.joined() : l.dropLast().joined(separator: ", ") + " and " + l.last!
}

// "a, b, c and 4 more": long lists cut short.
func andList(_ l: [String], atMost n: Int, more noun: String = "") -> String {
    l.count <= n ? andList(l) : l.prefix(n).joined(separator: ", ") + " and \(l.count - n) more" + (noun.isEmpty ? "" : " \(noun)")
}

// "4:05" until `end`.
func countdown(to end: Date, from now: Date) -> String {
    let sec = max(0, Int(end.timeIntervalSince(now)))
    return String(format: "%d:%02d", sec / 60, sec % 60)
}

// "a.com, b.com" or a pasted column of links: one entry each, in order, without repeats.
func splitList(_ text: String) -> [String] {
    var seen = Set<String>()
    return text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        .filter { seen.insert($0).inserted }
}
