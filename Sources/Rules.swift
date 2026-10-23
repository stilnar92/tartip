import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Enforcement rules

// All of these come from Settings (~/modes/settings.json).
var dailyFreeSeconds: Int { S.dailyFreeMinutes * 60 }       // rest + idle allowed per day
var idleNudgeSeconds: Int { S.idleNudgeMinutes * 60 }       // idle this long → prompt
var promptCountdown: Double { Double(S.promptCountdownSeconds) }
var minMinutes: Int { S.minMinutes }                         // no session shorter than this
var durationOptions: [Int] { S.durationOptions.filter { $0 >= S.minMinutes }.sorted() }
var defaultMinutes: Int { max(S.defaultMinutes, S.minMinutes) }
// Rest lengths offered, never longer than the per-stretch cap.
var restOptions: [Int] { [15, 30, 45, 60, 90, 120].filter { $0 <= S.maxRestMinutes } }

func durationLabel(_ m: Int) -> String { m == 60 ? "1h" : "\(m)" }

// Guard days and hours from Settings (default weekdays 10:00–22:00). Never at night.
func enforcementActive(_ d: Date) -> Bool {
    let cal = Calendar.current
    let wd = cal.component(.weekday, from: d)          // 1 = Sunday
    let h = cal.component(.hour, from: d)
    return S.guardDays.contains(wd) && h >= S.guardFromHour && h < S.guardToHour && !isNight(d)
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
