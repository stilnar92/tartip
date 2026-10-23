import Foundation
import Testing
@testable import FocusModes

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
