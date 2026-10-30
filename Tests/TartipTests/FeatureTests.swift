import Foundation
import Testing

@testable import Tartip

@Suite struct FeatureTests {
    @Test func freshInstallIsUsefulWithoutOptionalBehavior() throws {
        let fresh = AppSettings.fresh
        #expect(fresh.activities.map(\.name) == ["Focus"])
        #expect(Feature.allCases.allSatisfy { !fresh.has($0) })
        #expect(!fresh.isNight(at: Date()))
        #expect(fresh.autoStartAfterMinutes == 0)
        let loaded = try #require(AppSettings.merged(over: JSONEncoder().encode(fresh)))
        #expect(loaded == fresh)
        #expect(SessionPolicy(settings: loaded) == SessionPolicy(blocking: false, review: false))
    }

    @Test func legacyPartialSettingsRetainBehavior() throws {
        let old = try #require(AppSettings.merged(over: Data(#"{"defaultMinutes":45,"nightEnabled":false,"autoStartAfterMinutes":0}"#.utf8)))
        #expect(Feature.allCases.allSatisfy { old.has($0) })
        #expect(old.defaultMinutes == 45)
        #expect(!old.nightEnabled)
        #expect(old.autoStartAfterMinutes == 0)
    }

    @Test func disablingScheduleRetainsItsConfigurationButRemovesRestrictions() throws {
        var s = AppSettings.fresh
        var activity = ActivitySetting(name: "Work", dailyMinutes: 1, fromMinute: 0, toMinute: 1)
        activity.days = [1]
        s.activities = [activity]
        let now = Date()
        let record = SessionRecord(start: now.addingTimeInterval(-120), end: now, mode: "Work", planned: "Work")
        let manual = Limits(settings: s, today: [record], now: now)
        #expect(manual.canStart("Work"))
        #expect(manual.secondsLeftToday("Work") == nil)
        #expect(manual.sessionSeconds("Work", requested: 1800) == 1800)
        s.features.enabled.insert(.scheduling)
        #expect(Limits(settings: s, today: [record], now: now).secondsLeftToday("Work") == 0)
        #expect(s.activities[0] == activity)
    }

    @Test func policySurvivesActiveAndPausedStateRestoration() throws {
        var s = Session(block: "Work", phases: [Phase(isBreak: false, minutes: 30)], start: Date(), planned: "Work")
        s.policy = SessionPolicy(settings: .fresh)
        for phase in [AppPhase.session(s), .away(since: Date(), paused: s)] {
            let restored = try JSONDecoder().decode(AppPhase.self, from: JSONEncoder().encode(phase))
            #expect(restored == phase)
        }
        var settings = AppSettings.fresh
        settings.features = .legacy
        #expect(!s.policy.blocking && !s.policy.review)
        #expect(SessionPolicy(settings: settings).blocking)
    }

    @Test func legacySessionsKeepTheirCommitments() throws {
        let raw = Data(#"{"block":"Work","phases":[{"isBreak":false,"minutes":30}],"start":0}"#.utf8)
        let session = try JSONDecoder().decode(Session.self, from: raw)
        #expect(session.policy == .legacy)
    }

    @Test func restrictiveModulesCannotBypassSettingsLock() {
        let old = AppSettings()
        for feature in [Feature.blocking, .scheduling, .review, .guidance, .night, .settingsLock, .login, .relaunch] {
            var new = old
            new.features.enabled.remove(feature)
            #expect(!loosenings(from: old, to: new).isEmpty)
        }
    }

    @Test func tasksDoNotRequireReviewsAndLoginDoesNotImplyRelaunch() {
        var s = AppSettings.fresh
        s.features.enabled = [.tasks, .login]
        #expect(s.has(.tasks))
        #expect(!s.has(.review))
        #expect(!s.has(.guidance))
        #expect(!s.has(.relaunch))
        s.features.enabled = [.relaunch]
        #expect(!s.has(.relaunch))
    }

    @Test @MainActor func launchAgentSeparatesLoginFromKeepAlive() {
        let manualQuit = AutoStart.agent("/Applications/Tartip.app/Contents/MacOS/Tartip", keepAlive: false)
        #expect(manualQuit["RunAtLoad"] as? Bool == true)
        #expect(manualQuit["KeepAlive"] as? Bool == false)
        #expect(AutoStart.agent("/tmp/legacy")["KeepAlive"] as? Bool == true)
    }

    @Test func unreviewedTimeDoesNotClaimConfirmedWork() {
        let r = SessionRecord(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 120), mode: "Focus", planned: "Focus")
        #expect(!r.asPlanned)
        #expect(r.actual.isEmpty)
        #expect(secondsByActivity([r])["Focus"] == 120)
        #expect(r.completedTasks == nil)
    }
    @Test func completionRecordsTimeWithoutInventingAReview() throws {
        let start = Date(timeIntervalSince1970: 1000.5)
        var session = Session(block: "Focus", phases: [Phase(isBreak: false, minutes: 30)], start: start, planned: "Focus")
        session.policy = SessionPolicy(settings: .fresh)
        session.paused = 60
        let r = try #require(session.completedRecord(at: start.addingTimeInterval(180), ended: "stopped"))
        #expect(r.seconds == 120)
        #expect(r.actual.isEmpty)
        #expect(r.began == start)
        #expect(r.paused == 60)
        #expect(r.ended == "stopped")
        #expect(session.completedRecord(at: start.addingTimeInterval(90), ended: "stopped") == nil)
        let ended = try #require(session.completedRecord(at: start.addingTimeInterval(9000), ended: "done"))
        #expect(ended.seconds == 1800)
    }

    @Test func completionOutboxSurvivesRestartAndMatchesHistoryDates() throws {
        let session = Session(block: "Focus", phases: [Phase(isBreak: false, minutes: 1)], start: Date(timeIntervalSince1970: 1000.75), planned: "Focus")
        let record = try #require(session.completedRecord(at: session.end, ended: "done"))
        var state = StoredState()
        state.pendingRecords = [record]
        let loaded = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(state))
        #expect(loaded.pendingRecords == [record])
        let history = try recordDecoder().decode(SessionRecord.self, from: recordEncoder().encode(record))
        #expect(history.isSameSession(as: record))
    }

    @Test func disabledNightDoesNotShortenTheDisplayedDay() {
        var s = AppSettings()
        s.features.enabled.remove(.night)
        #expect(wakingHours(s).from == 0)
        #expect(wakingHours(s).to == 1440)
    }

    @Test func unknownFutureFeaturesDoNotDiscardKnownSettings() throws {
        let raw = Data(#"{"features":{"enabled":["tasks","futureFeature"]},"defaultMinutes":45}"#.utf8)
        let s = try #require(AppSettings.merged(over: raw))
        #expect(s.has(.tasks))
        #expect(!s.has(.guidance))
        #expect(s.defaultMinutes == 45)
    }

}
