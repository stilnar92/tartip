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

    // Reviewing as "Not planned" is just another name: it records honestly instead of
    // crediting the planned activity, without being a real activity itself.
    @Test func notPlannedReplacesThePlanInStats() {
        let r = SessionRecord(start: at(10), end: at(10, 30), mode: "Work", planned: "Work", actual: [notPlannedActivity])
        #expect(secondsByActivity([r]) == [notPlannedActivity: 1800])
    }

    @Test func sessionCrossingMidnightCountsOnlyItsPartOfTheDay() {
        let r = SessionRecord(start: at(23, 40), end: at(0, 20, day: 2), mode: "Work", planned: "Work")
        let today = records([r], since: at(0, day: 2))
        #expect(today.first?.seconds == 1200)
        #expect(records([r], since: at(1, day: 2)).isEmpty)
    }

    @Test func boundedRangeExcludesTheNextDay() {
        let yesterday = SessionRecord(start: at(10, day: 1), end: at(11, day: 1), mode: "Work", planned: "Work")
        let today = SessionRecord(start: at(10, day: 2), end: at(11, day: 2), mode: "Work", planned: "Work")
        let out = records([yesterday, today], from: at(0, day: 1), to: at(0, day: 2))
        #expect(out.count == 1)
        #expect(out.first?.seconds == 3600)
    }

    @Test func boundedRangeClipsASessionCrossingTheUpperBound() {
        let r = SessionRecord(start: at(23, 40, day: 1), end: at(0, 20, day: 3), mode: "Work", planned: "Work")
        let out = records([r], from: at(0, day: 2), to: at(0, day: 3))
        #expect(out.first?.seconds == 24 * 3600)
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

    @Test func forcedBreakDefaultsAreOnlyActiveWhenEnabled() {
        let s = AppSettings()
        #expect(s.forceBreakAfterHours == 2)
        #expect(s.forceBreakCooldownMinutes == 1)
        #expect(!s.has(.forcedBreak))         // the threshold alone doesn't turn it on
        #expect(!AppSettings.fresh.has(.forcedBreak))
    }

    // Old settings files never had stepAwayMinutes: they must load with 0 (no minimum),
    // matching Step away's behavior before this setting existed.
    @Test func stepAwayMinutesDefaultsToNoMinimum() throws {
        let s = try #require(AppSettings.merged(over: Data(#"{"dailyFreeMinutes": 90}"#.utf8)))
        #expect(s.stepAwayMinutes == 0)
    }

    // Settings saved before multiple windows existed have fromMinute/toMinute, not windows:
    // that single pair must fold into one window with no user action.
    @Test func legacySingleWindowMigratesIntoWindowsArray() throws {
        let json = #"{"name": "Work", "fromMinute": 600, "toMinute": 720}"#
        let a = try JSONDecoder().decode(ActivitySetting.self, from: Data(json.utf8))
        #expect(a.windows == [TimeWindow(id: a.windows[0].id, from: 600, to: 720)])
    }

    @Test func noHoursAtAllMigratesToAnyTime() throws {
        let json = #"{"name": "Work"}"#
        let a = try JSONDecoder().decode(ActivitySetting.self, from: Data(json.utf8))
        #expect(a.windows.isEmpty)
    }

    @Test func multiWindowActivityRoundTripsThroughEncoding() throws {
        let a = ActivitySetting(name: "Work", windows: [TimeWindow(from: 600, to: 720), TimeWindow(from: 960, to: 1080)])
        let back = try JSONDecoder().decode(ActivitySetting.self, from: JSONEncoder().encode(a))
        #expect(back.windows == a.windows)
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

    @Test func multipleWindowsOpenInEachAndClosedInTheGap() {
        var s = AppSettings()
        s.activities = [ActivitySetting(name: "Work", windows: [TimeWindow(from: 10 * 60, to: 12 * 60), TimeWindow(from: 16 * 60, to: 18 * 60)])]
        #expect(Limits(settings: s, today: [], now: at(11), calendar: cal).isOpen("Work"))
        #expect(Limits(settings: s, today: [], now: at(17), calendar: cal).isOpen("Work"))
        let gap = Limits(settings: s, today: [], now: at(14), calendar: cal)
        #expect(!gap.isOpen("Work"))
        #expect(gap.opensLabel("Work") == "from 16:00")   // soonest upcoming window, not always the first
        // After both windows close for the day, the soonest (wrapping to tomorrow) is the first one again.
        let afterBoth = Limits(settings: s, today: [], now: at(19), calendar: cal)
        #expect(!afterBoth.isOpen("Work"))
        #expect(afterBoth.opensLabel("Work") == "from 10:00")
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

    @Test func forcedBreakPhaseSurvivesEncoding() throws {
        var s = StoredState()
        s.phase = .forcedBreak(until: at(10, 1))
        let back = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.phase.forcedBreakUntil == at(10, 1))
    }

    @Test func activeSinceSurvivesAndOldStateLoadsWithout() throws {
        var s = StoredState()
        let old = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s))   // saved before activeSince
        #expect(old.activeSince == nil)
        s.activeSince = at(9)
        #expect(try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test func stepAwayUntilSurvivesAndOldStateLoadsWithout() throws {
        var s = StoredState()
        let old = try JSONDecoder().decode(StoredState.self, from: JSONEncoder().encode(s))   // saved before stepAwayUntil
        #expect(old.stepAwayUntil == nil)
        s.stepAwayUntil = at(9, 35)
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

@Suite struct FreeTimeLengthTests {
    private func lengths(cap: Int) -> [Int] {
        var s = AppSettings()
        s.maxRestMinutes = cap
        return s.freeTimeLengths
    }

    @Test func theCapIsAlwaysOffered() {
        #expect(lengths(cap: 10) == [10])            // under the smallest standard length
        #expect(lengths(cap: 40) == [15, 30, 40])
        #expect(lengths(cap: 60) == [15, 30, 45, 60])
    }

    @Test func alwaysFreeMinutesAreExcludedFromTheExtendedList() {
        var s = AppSettings()
        s.alwaysFreeMinutes = 20
        s.maxRestMinutes = 60
        #expect(s.freeTimeLengths == [30, 45, 60])   // 15 is covered by the always-free tier

        s.alwaysFreeMinutes = 60
        s.maxRestMinutes = 60
        #expect(s.freeTimeLengths == [])             // the cap itself is no longer "extended"
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

    // A real activity named "Other" is just an activity: its own block applies, not otherBlock.
    @Test func anActivityNamedOtherUsesItsOwnBlock() {
        var s = AppSettings()
        s.otherBlock = "Focus_Mode"
        s.activities = [ActivitySetting(name: otherActivity)]
        #expect(s.block(for: otherActivity) == otherActivity)
        #expect(s.block(for: otherActivity) != s.otherBlock)
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

    @Test func pastedList() {
        #expect(splitList("a.com, b.com,c.com") == ["a.com", "b.com", "c.com"])
        #expect(splitList(" x.com\ny.com  x.com ,") == ["x.com", "y.com"])
        #expect(splitList("  ").isEmpty)
    }
}

@Suite struct RecordFieldsTests {
    @Test func oldLinesStillLoad() throws {
        let json = #"{"start":"2026-03-01T10:00:00Z","end":"2026-03-01T10:30:00Z","mode":"Work","planned":"Work","actual":["Work"]}"#
        let r = try recordDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        #expect(r.seconds == 1800)
        #expect(r.began == nil && r.ended == nil && r.auto == nil)
    }

    @Test func newFieldsRoundTripAndOnlyWhenKnown() throws {
        var r = SessionRecord(start: at(10, 10), end: at(10, 40), mode: "Work", planned: "Work")
        let bare = String(data: try recordEncoder().encode(r), encoding: .utf8)!
        #expect(!bare.contains("began") && !bare.contains("auto"))
        r.began = at(10); r.paused = 600; r.plannedMinutes = 30; r.ended = "done"; r.auto = true; r.pickSeconds = 42
        #expect(try recordDecoder().decode(SessionRecord.self, from: recordEncoder().encode(r)) == r)
    }

    @Test func savedStateFromBeforeStillLoads() throws {
        let json = #"{"block":"Work","phases":[{"isBreak":false,"minutes":30}],"start":0,"paused":60}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(s.paused == 60 && s.auto == nil && s.pickSeconds == nil)
    }
}

@Suite struct InsightsTests {
    @Test func numbers() {
        var a = SessionRecord(start: at(10), end: at(10, 30), mode: "Work", planned: "Work")
        a.ended = "done"; a.pickSeconds = 30
        var b = SessionRecord(start: at(11), end: at(11, 10), mode: "Work", planned: "Work")
        b.ended = "stopped"; b.auto = true; b.pickSeconds = 900
        var c = SessionRecord(start: at(12), end: at(12, 30), mode: "Work", planned: "Work")
        c.pickSeconds = 60
        let old = SessionRecord(start: at(9), end: at(9, 30), mode: "Work", planned: "Work")
        let events = [Event(t: at(13), type: "free", seconds: 600, minutes: 15),
                      Event(t: at(14), type: "blocked", name: "youtube.com", block: "Work"),
                      Event(t: at(15), type: "blocked", name: "youtube.com", block: "Work"),
                      Event(t: at(15), type: "blocked", name: "ru.keepcoder.Telegram", block: "Work"),
                      Event(t: at(9, day: 2), type: "blocked", name: "x.com", block: "Work")]   // outside the range
        let away = [AwayRecord(start: at(16), end: at(16, 20)),
                    AwayRecord(start: at(1), end: at(7))]                                      // sleep
        let i = insights([old, a, b, c], events: events, away: away, from: at(0), to: at(0, day: 2))
        #expect(i.finished == 50)          // old has no `ended`, so it isn't counted either way
        #expect(i.autoStarted == 1)
        #expect(i.pickMedian == 60)
        #expect(i.free == 600)
        #expect(i.away == 1200)
        #expect(i.blocked == [.init(name: "youtube.com", count: 2), .init(name: "ru.keepcoder.Telegram", count: 1)])
    }

    // Said reasons, split evenly when several; unexplained time is "Not said", but only once
    // something was said — and sleep (over 3 h) is never counted.
    @Test func awayReasons() {
        let away = [AwayRecord(start: at(10), end: at(10, 30), did: ["Walk"]),
                    AwayRecord(start: at(12), end: at(12, 20), did: ["Meal"], note: "Call with mom"),
                    AwayRecord(start: at(14), end: at(14, 15)),
                    AwayRecord(start: at(1), end: at(7), did: ["Sleep"])]
        let i = insights([], events: [], away: away, from: at(0), to: at(0, day: 2))
        #expect(i.awayReasons == [.init(name: "Walk", seconds: 1800), .init(name: "Call with mom", seconds: 600),
                                  .init(name: "Meal", seconds: 600), .init(name: notSaidAway, seconds: 900)])
        let unasked = insights([], events: [], away: [AwayRecord(start: at(14), end: at(14, 15))], from: at(0), to: at(0, day: 2))
        #expect(unasked.awayReasons.isEmpty)
    }

    @Test func asksAboutAwayOnlyWhenOnAndInRange() {
        var s = AppSettings()
        #expect(!s.asksAboutAway(seconds: 600))                // off by default
        s.awayAsk = .text
        #expect(!s.asksAboutAway(seconds: 4 * 60 + 59))
        #expect(s.asksAboutAway(seconds: 5 * 60))
        #expect(s.asksAboutAway(seconds: 3 * 3600))
        #expect(!s.asksAboutAway(seconds: 3 * 3600 + 1))       // sleep
        s.features.enabled.remove(.away)
        #expect(!s.asksAboutAway(seconds: 600))
    }

    @Test func awayLinesFromBeforeStillLoad() throws {
        let old = try recordDecoder().decode(AwayRecord.self, from: Data(#"{"start":"2026-10-27T15:41:52Z","end":"2026-10-27T16:01:36Z"}"#.utf8))
        #expect(old.did == nil && old.note == nil && old.reasons.isEmpty)
    }

    // The question survives a restart, with the paused session still waiting behind it.
    @Test func awayReviewPhaseRoundTrips() throws {
        let s = Session(block: "Work", phases: [Phase(isBreak: false, minutes: 30)], start: at(10), planned: "Work")
        let phase = AppPhase.awayReview(since: at(10, 5), back: at(10, 20), paused: s)
        let decoded = try JSONDecoder().decode(AppPhase.self, from: JSONEncoder().encode(phase))
        #expect(decoded == phase && decoded.hasOpenSession && !decoded.canStart)
        #expect(decoded.awayStretch?.back == at(10, 20))
    }

    @Test func onlyTheHostOfABlockedSite() {
        #expect(siteName("https://www.youtube.com/watch?v=abc") == "youtube.com")
        #expect(siteName("file:///Users/x/a.html") == nil)
    }
}

@Suite struct RemainingSessionTests {
    @Test func capsLongSessionsAndAllowsOptOut() {
        var settings = AppSettings()
        settings.activities = [ActivitySetting(name: "PrepareDay", dailyMinutes: 15)]
        let limits = Limits(settings: settings, today: [], now: at(10), calendar: cal)
        #expect(limits.sessionSeconds("PrepareDay", requested: 3600) == 900)
        #expect(limits.sessionSeconds("PrepareDay", requested: 300) == 300)
        #expect(limits.sessionSeconds("Other", requested: 3600) == 3600)
        settings.capSessionsToRemainingTime = false
        #expect(Limits(settings: settings, today: [], now: at(10), calendar: cal)
            .sessionSeconds("PrepareDay", requested: 3600) == 3600)
    }

    @Test func exactCapEndsPomodoroAndSurvivesPersistence() throws {
        var session = Session(block: "Work", phases: [Phase(isBreak: false, minutes: 25),
            Phase(isBreak: true, minutes: 5), Phase(isBreak: false, minutes: 25)], start: at(10))
        session.maxDurationSeconds = 47
        #expect(session.end == at(10).addingTimeInterval(47))
        #expect(session.current(at: at(10))?.end == session.end)
        #expect(session.current(at: session.end) == nil)
        session.paused = 60
        #expect(session.end == at(10).addingTimeInterval(107))
        #expect(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)) == session)
    }

    @Test func oldSettingsEnableCap() {
        #expect(AppSettings.merged(over: Data("{}".utf8))?.capSessionsToRemainingTime == true)
    }
}
