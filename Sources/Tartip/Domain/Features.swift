import Foundation

// Persisted choices and shared dependency policy. Missing legacy settings enable the
// old capabilities; fresh installs explicitly persist an empty selection.
enum Feature: String, Codable, CaseIterable, Identifiable {
    case blocking, workspace, tasks, pomodoro, scheduling, review, guidance, night
    case settingsLock, statistics, login, relaunch, notifications, away
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blocking: "Distraction blocking"
        case .workspace: "Open a workspace"
        case .tasks: "Daily tasks"
        case .pomodoro: "Pomodoro"
        case .scheduling: "Schedules and daily limits"
        case .review: "Session review"
        case .guidance: "Continuous guidance"
        case .night: "Night rules"
        case .settingsLock: "Settings lock"
        case .statistics: "Detailed statistics"
        case .login: "Launch at login"
        case .relaunch: "Relaunch after quitting"
        case .notifications: "Notifications"
        case .away: "Step away"
        }
    }
    var detail: String {
        switch self {
        case .blocking: "Configure apps and sites in Activities → Edit. Existing locks last until their deadline."
        case .workspace: "Open apps, links and files when a session starts. Configure them in Activities → Edit."
        case .tasks: "Plan and check off daily tasks for each activity."
        case .pomodoro: "Alternate focus rounds with short breaks."
        case .scheduling: "Set available days, hours and daily limits."
        case .review: "Ask what you worked on after each session. Changes apply to future sessions."
        case .guidance: "Keep an unclosable What's next? window open while idle. Auto-start and free-time budgets are configured below."
        case .night: "Reserve nighttime and optionally block distractions until morning."
        case .settingsLock: "Limit when settings can be loosened."
        case .statistics: "Explore your recorded sessions and activity totals."
        case .login: "Start Tartip when you sign in."
        case .relaunch: "Keep Tartip running after a quit. Requires Launch at login."
        case .notifications: "Play sounds and show session notifications."
        case .away: "Lock the screen and keep the Mac awake while away."
        }
    }
}

struct Features: Codable, Equatable {
    var enabled: Set<Feature> = []
    init(enabled: Set<Feature> = []) { self.enabled = enabled }
    private enum CodingKeys: String, CodingKey { case enabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let names = try c.decodeIfPresent([String].self, forKey: .enabled) ?? []
        enabled = Set(names.compactMap(Feature.init(rawValue:)))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled.map(\.rawValue).sorted(), forKey: .enabled)
    }
    static let legacy = Features(enabled: Set(Feature.allCases))
    func contains(_ feature: Feature) -> Bool {
        enabled.contains(feature) && (feature != .relaunch || enabled.contains(.login))
    }
}

extension AppSettings {
    func has(_ feature: Feature) -> Bool { features.contains(feature) }
    static var fresh: AppSettings {
        var s = AppSettings()
        s.features = Features()
        s.nightEnabled = false
        s.autoStartAfterMinutes = 0
        s.dailyFreeMinutes = 0
        s.activities = [ActivitySetting(name: "Focus")]
        return s
    }
}

// A session keeps its original commitments across edits, restarts and time away.
struct SessionPolicy: Codable, Equatable {
    var blocking: Bool
    var review: Bool
    static let legacy = SessionPolicy(blocking: true, review: true)
    init(settings: AppSettings) {
        blocking = settings.has(.blocking)
        review = settings.has(.review)
    }
    init(blocking: Bool, review: Bool) {
        self.blocking = blocking
        self.review = review
    }
}
