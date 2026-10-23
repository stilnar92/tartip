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
