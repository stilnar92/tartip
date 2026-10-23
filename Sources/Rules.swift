import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Enforcement rules

let dailyFreeSeconds = 60 * 60        // rest + idle allowed per day
let idleNudgeSeconds = 15 * 60        // idle this long → prompt
let promptCountdown: Double = 60      // prompt auto-starts after this
let autoMinutes = 15                  // auto-start locks the minimum; the picker can extend it
let minMinutes = 15                   // no session shorter than this
let durationOptions = [15, 20, 30, 45, 60]
let defaultMinutes = 30
func durationLabel(_ m: Int) -> String { m == 60 ? "1h" : "\(m)" }

// Weekdays 10:00–22:00.
func enforcementActive(_ d: Date) -> Bool {
    let cal = Calendar.current
    let wd = cal.component(.weekday, from: d)          // 1 = Sunday
    let h = cal.component(.hour, from: d)
    return (2...6).contains(wd) && (10..<22).contains(h)
}

// At the computer: input in the last 2 minutes and screen not locked.
func userPresent() -> Bool {
    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    if idle > 120 { return false }
    if let d = CGSessionCopyCurrentDictionary() as? [String: Any], d["CGSSessionScreenIsLocked"] as? Bool == true { return false }
    return true
}

func dayKey(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

struct DayStats: Codable {
    var day: String
    var free = 0        // seconds of rest + idle
    var focus = 0
    var thinking = 0
}

enum PromptKind: Equatable {
    case idle, budget, restOver

    var title: String {
        switch self {
        case .idle: return "15 minutes without a mode"
        case .budget: return "Today's free time is used up"
        case .restOver: return "Rest is over"
        }
    }

    // The prompt always starts Thinking (Strict only if there's no Thinking block).
    var startsStrict: Bool { false }
}

struct Prompt: Equatable {
    var kind: PromptKind
    var deadline: Date
}
