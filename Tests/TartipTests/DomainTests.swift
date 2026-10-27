import Foundation
import Testing
@testable import Tartip

// Dates in a fixed calendar, so the tests don't depend on the machine's time zone.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func at(_ h: Int, _ m: Int = 0, day: Int = 1) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}

@Suite struct SessionTests {
    let pomodoro = Session(block: "Work", phases: [Phase(isBreak: false, minutes: 25), Phase(isBreak: true, minutes: 5),
                                                   Phase(isBreak: false, minutes: 25)], start: at(10))

    @Test func currentPhase() {
        #expect(pomodoro.current(at: at(10, 10))?.index == 0)
        #expect(pomodoro.current(at: at(10, 25))?.index == 1)
        #expect(pomodoro.current(at: at(10, 30))?.end == at(10, 55))
        #expect(pomodoro.current(at: at(10, 55)) == nil)
    }

    @Test func timeAwayMovesTheRest() {
        var s = pomodoro
        s.paused = 10 * 60
        #expect(s.end == at(11, 5))
        #expect(s.current(at: at(10, 30))?.index == 0)     // 20 min in, not 30
        #expect(s.current(at: at(10, 36))?.index == 1)     // the break moved to 10:35–10:40
        #expect(s.current(at: at(10, 40))?.end == at(11, 5))
    }

    @Test func oldSessionLoadsWithoutTimeAway() throws {
        let json = #"{"block":"Work","phases":[{"isBreak":false,"minutes":30}],"start":0}"#
        #expect(try JSONDecoder().decode(Session.self, from: Data(json.utf8)).paused == 0)
    }

    @Test func rounds() {
        #expect(pomodoro.workRounds == 2)
        #expect(pomodoro.totalMinutes == 55)
        #expect(pomodoro.round(of: 2) == 2)
    }
}

@Suite struct NightTests {
    @Test func windowCrossingMidnight() {
        #expect(inWindow(23 * 60, 22 * 60, 6 * 60))
        #expect(inWindow(3 * 60, 22 * 60, 6 * 60))
        #expect(!inWindow(6 * 60, 22 * 60, 6 * 60))
        #expect(inWindow(12 * 60, 12 * 60, 20 * 60))
        #expect(!inWindow(20 * 60, 12 * 60, 20 * 60))
    }

    @Test func isNight() {
        var s = AppSettings()             // 00:00–08:00
        #expect(s.isNight(at: at(3), calendar: cal))
        #expect(!s.isNight(at: at(8), calendar: cal))
        s.nightEnabled = false
        #expect(!s.isNight(at: at(3), calendar: cal))
    }

    @Test func nightEndIsTheNextMorning() {
        var s = AppSettings()
        s.nightFrom = 22 * 60; s.nightTo = 6 * 60
        #expect(s.nightEnd(after: at(23), calendar: cal) == at(6, day: 2))
        #expect(s.nightEnd(after: at(2), calendar: cal) == at(6))
    }
}

@Suite struct LimitsTests {
    @Test func reviewedTimeGoesToWhatWasDone() {
        let r = SessionRecord(start: at(10), end: at(10, 30), mode: "Work", planned: "Work", actual: ["English"])
        #expect(secondsByActivity([r]) == ["English": 1800])
    }

    @Test func unreviewedTimeGoesToThePlan() {
        let r = SessionRecord(start: at(10), end: at(10, 30), mode: "Work", planned: "Work")
        #expect(secondsByActivity([r]) == ["Work": 1800])
    }

    @Test func sessionCrossingMidnightCountsOnlyItsPartOfTheDay() {
        let r = SessionRecord(start: at(23, 40), end: at(0, 20, day: 2), mode: "Work", planned: "Work")
        let today = records([r], since: at(0, day: 2))
        #expect(today.first?.seconds == 1200)
        #expect(records([r], since: at(1, day: 2)).isEmpty)
    }

    @Test func splitKeepsEverySecond() {
        let r = SessionRecord(start: at(10), end: at(10, 0).addingTimeInterval(100), mode: "Work",
                              planned: "Work", actual: ["A", "B", "C"])
        let out = secondsByActivity([r])
        #expect(out.values.reduce(0, +) == 100)
        #expect(out["A"] == 34)
    }
}

@Suite struct StorageTests {
    @Test func missingSettingsGetTheirDefault() throws {
        let s = try #require(AppSettings.merged(over: Data(#"{"dailyFreeMinutes": 90}"#.utf8)))
        #expect(s.dailyFreeMinutes == 90)
        #expect(s.pomodoroRounds == AppSettings().pomodoroRounds)
    }

    @Test func modeConfigWithoutKeys() throws {
        let c = try JSONDecoder().decode(ModeConfig.self, from: Data("{}".utf8))
        #expect(c == ModeConfig())
    }
}

@Suite struct ActivityLimitsTests {
    var settings: AppSettings {
        var s = AppSettings()
        s.activities = [ActivitySetting(name: "Work", dailyMinutes: 60, fromMinute: 12 * 60, toMinute: 20 * 60),
                        ActivitySetting(name: "English")]
        return s
    }

    @Test func timeLeftCountsTodaysSessions() {
        let today = [SessionRecord(start: at(13), end: at(13, 40), mode: "Work", planned: "Work")]
        let limits = Limits(settings: settings, today: today, now: at(14), calendar: cal)
        #expect(limits.secondsLeftToday("Work") == 20 * 60)
        #expect(limits.secondsLeftToday("English") == nil)
        #expect(limits.canStart("Work"))
    }

    @Test func closedOutsideItsHours() {
        let limits = Limits(settings: settings, today: [], now: at(9), calendar: cal)
        #expect(!limits.isOpen("Work"))
        #expect(limits.opensLabel("Work") == "from 12:00")
        #expect(limits.isOpen("English"))
    }

    @Test func autoPickPrefersTheActivityFurthestBehind() {
        var s = AppSettings()
        s.activities = [ActivitySetting(name: "Work", dailyMinutes: 60),
                        ActivitySetting(name: "Arabic", dailyMinutes: 90),
                        ActivitySetting(name: "English"),
                        ActivitySetting(name: "Rest", dailyMinutes: 30)]
        let names = s.activities.map(\.name)
        let today = [SessionRecord(start: at(10), end: at(11), mode: "Arabic", planned: "Arabic")]
        // Work has 60m left, Arabic 30m: Work is furthest behind.
        #expect(Limits(settings: s, today: today, now: at(14), calendar: cal).autoPick(from: names) == "Work")
        // Work used up: Arabic is the only limited one left.
        let workDone = today + [SessionRecord(start: at(12), end: at(13), mode: "Work", planned: "Work")]
        #expect(Limits(settings: s, today: workDone, now: at(14), calendar: cal).autoPick(from: names) == "Arabic")
    }

    @Test func autoPickSkipsClosedAndRest() {
        var s = AppSettings()
        s.activities = [ActivitySetting(name: "Work", dailyMinutes: 60, fromMinute: 12 * 60, toMinute: 20 * 60),
                        ActivitySetting(name: "Rest", dailyMinutes: 30),
                        ActivitySetting(name: "English")]
        let names = s.activities.map(\.name)
        // At 9:00 Work is closed; Rest is skipped while something else can start.
        #expect(Limits(settings: s, today: [], now: at(9), calendar: cal).autoPick(from: names) == "English")
        // Only Rest can start: then it's Rest.
        #expect(Limits(settings: s, today: [], now: at(9), calendar: cal).autoPick(from: ["Work", "Rest"]) == "Rest")
    }

    @Test func pomodoroPhases() {
        let phases = AppSettings().pomodoroPhases()
        #expect(phases.count == 7)
        #expect(phases.filter(\.isBreak).count == 3)
    }
}

@Suite struct StateStoreTests {
    @Test func phaseSurvivesEncoding() throws {
        var s = StoredState()
        s.phase = .freeTime(start: at(10), end: at(10, 30))
        let back = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func roundSurvivesAndOldStateLoadsWithout() throws {
        var s = StoredState()
        let old = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s))   // saved before rounds
        #expect(old.round == nil)
        s.round = Round(day: "2026-03-01", number: 2, since: at(11))
        #expect(try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test func migratesTheOldKeys() throws {
        let name = "TartipTests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let session = Session(block: "Work", phases: [Phase(isBreak: false, minutes: 30)], start: at(10), planned: "Work")
        d.set(try JSONEncoder().encode(session), forKey: "session")
        d.set(45, forKey: "minutes")
        d.set(true, forKey: "restTaken")
        d.set(try JSONEncoder().encode(DayStats(day: "2026-03-01", free: 600)), forKey: "stats")

        let s = StateStore.migrate(from: d, now: at(10, 10))
        #expect(s.phase == .session(session))
        #expect(s.minutes == 45)
        #expect(s.restTaken)
        #expect(s.freeUsed.free == 600)
        // A session that ended while the app was gone isn't restored.
        #expect(StateStore.migrate(from: d, now: at(11)).phase == .idle)
    }
}

@Suite struct ActivityIdentityTests {
    @Test func oldActivityLoadsWithItsNameAsBlock() throws {
        let json = #"{"activities": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "name": "Work", "dailyMinutes": 60}]}"#
        let s = try #require(AppSettings.merged(over: Data(json.utf8)))
        #expect(s.activities.first?.block == "Work")
        #expect(s.activities.first?.opens == ModeConfig())
        #expect(s.activities.first?.dailyMinutes == 60)
    }

    @Test func opensWithoutFilesLoadsWithNone() throws {
        let json = #"{"activities": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "name": "Work", "opens": {"apps": ["/Applications/Xcode.app"], "urls": [], "maximize": false}}]}"#
        let s = try #require(AppSettings.merged(over: Data(json.utf8)))
        #expect(s.activities.first?.opens == ModeConfig(apps: ["/Applications/Xcode.app"], maximize: false))
    }

    @Test func renamingKeepsTheBlock() {
        var s = AppSettings()
        s.activities = [ActivitySetting(name: "Arabic")]
        s.activities[0].name = "Arabic lessons"
        #expect(s.block(for: "Arabic lessons") == "Arabic")
        #expect(s.block(for: otherActivity) == s.otherBlock)
    }
}

@Suite struct FormatTests {
    @Test func minutes() {
        #expect(minutesLabel(45) == "45m")
        #expect(minutesLabel(60) == "1h")
        #expect(minutesLabel(90) == "1h 30m")
        #expect(limitLabel(0) == "No limit")
        #expect(formatDuration(3_900) == "1h 5m")
    }
}
