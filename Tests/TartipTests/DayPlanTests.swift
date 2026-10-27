import Foundation
import Testing
@testable import Tartip

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

// 2026-03-02 is a Monday.
private func at(_ h: Int, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: h, minute: m))!
}

private let monday = 2

private func act(_ name: String, _ minutes: Int, _ from: Int? = nil, _ to: Int? = nil, days: [Int] = []) -> ActivitySetting {
    var a = ActivitySetting(name: name, dailyMinutes: minutes, fromMinute: from.map { $0 * 60 }, toMinute: to.map { $0 * 60 })
    a.days = days
    return a
}

private func settings(_ acts: [ActivitySetting]) -> AppSettings {
    var s = AppSettings()
    s.activities = acts
    s.nightFrom = 21 * 60
    s.nightTo = 9 * 60 + 30
    return s
}

private func hm(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

@Suite struct DayPlanTests {
    // Task 1 any time, Task 2 from 14:00, Task 3 from 16:00, the day 9:30–21:00.
    let example = settings([act("Task 1", 60), act("Task 2", 120, 14, 21), act("Task 3", 180, 16, 21)])

    @Test func wakingDayIsBetweenNights() {
        #expect(wakingHours(example) == (hm(9, 30), hm(21)))
        var off = example
        off.nightEnabled = false
        #expect(wakingHours(off) == (0, 1440))
    }

    @Test func theExampleInPeriods() {
        let w = wakingHours(example)
        #expect(availability(example, weekday: monday, from: w.from, to: w.to) == [
            Period(start: hm(9, 30), end: hm(14), available: ["Task 1"]),
            Period(start: hm(14), end: hm(16), available: ["Task 1", "Task 2"]),
            Period(start: hm(16), end: hm(21), available: ["Task 1", "Task 2", "Task 3"]),
        ])
    }

    @Test func nothingOpenIsAnEmptyPeriod() {
        let s = settings([act("Task 2", 120, 14, 21)])
        #expect(availability(s, weekday: monday, from: hm(9, 30), to: hm(21)) == [
            Period(start: hm(9, 30), end: hm(14), available: []),
            Period(start: hm(14), end: hm(21), available: ["Task 2"]),
        ])
    }

    @Test func periodsCloseToo() {
        let s = settings([act("Work", 60), act("English", 30, 13, 20)])
        #expect(availability(s, weekday: monday, from: hm(9, 30), to: hm(21)) == [
            Period(start: hm(9, 30), end: hm(13), available: ["Work"]),
            Period(start: hm(13), end: hm(20), available: ["Work", "English"]),
            Period(start: hm(20), end: hm(21), available: ["Work"]),
        ])
    }

    @Test func otherWeekdaysAreLeftOut() {
        let s = settings([act("Arabic", 60, days: [4])])   // Wednesdays only
        #expect(availability(s, weekday: monday, from: hm(10), to: hm(11)) == [Period(start: hm(10), end: hm(11), available: [])])
        #expect(availability(s, weekday: 4, from: hm(10), to: hm(11)).first?.available == ["Arabic"])
    }

    @Test func hoursCanCrossMidnight() {
        let s = settings([act("Late", 60, 23, 1)])
        #expect(availability(s, weekday: monday, from: hm(22), to: hm(26)) == [
            Period(start: hm(22), end: hm(23), available: []),
            Period(start: hm(23), end: hm(25), available: ["Late"]),
            Period(start: hm(25), end: hm(26), available: []),
        ])
    }

    @Test func pastDayMergesAndMarksNoSession() {
        let done = [PlanSlot(start: hm(19, 24), end: hm(19, 39), activity: "Work"),
                    PlanSlot(start: hm(18, 38), end: hm(18, 53), activity: "Project"),
                    PlanSlot(start: hm(19, 9), end: hm(19, 24), activity: "Work")]
        #expect(pastDay(done, from: hm(8), until: hm(19, 41)) == [
            PlanSlot(start: hm(8), end: hm(18, 38), activity: nil),
            PlanSlot(start: hm(18, 38), end: hm(18, 53), activity: "Project"),
            PlanSlot(start: hm(18, 53), end: hm(19, 9), activity: nil),
            PlanSlot(start: hm(19, 9), end: hm(19, 39), activity: "Work"),
        ])
    }

    @Test func awayStaysApartAndOverlapsAreTrimmed() {
        let slots = [PlanSlot(start: hm(10), end: hm(10, 40), activity: nil, away: true),
                     PlanSlot(start: hm(10, 30), end: hm(11), activity: "Work")]
        #expect(pastDay(slots, from: hm(10), until: hm(11)) == [
            PlanSlot(start: hm(10), end: hm(10, 40), activity: nil, away: true),
            PlanSlot(start: hm(10, 40), end: hm(11), activity: "Work"),
        ])
    }

    // MARK: when the app starts a new round

    private func limits(_ s: AppSettings, done: [String: Int], at now: Date) -> Limits {
        let recs = done.map { SessionRecord(start: at(9, 30), end: at(9, 30).addingTimeInterval(Double($0.value * 60)),
                                            mode: $0.key, planned: $0.key) }
        return Limits(settings: s, today: recs, now: now, calendar: cal)
    }

    @Test func noRoundWhileSomethingCanStart() {
        let l = limits(example, done: ["Task 1": 30], at: at(10))
        #expect(!l.needsNewRound(["Task 1", "Task 2", "Task 3"]))
    }

    @Test func roundInTheGap() {
        let l = limits(example, done: ["Task 1": 60], at: at(11))
        #expect(l.needsNewRound(["Task 1", "Task 2", "Task 3"]))
    }

    @Test func noRoundAtNight() {
        let l = limits(example, done: ["Task 1": 60], at: at(22))
        #expect(!l.needsNewRound(["Task 1", "Task 2", "Task 3"]))
    }

    @Test func noRoundWithNothingPlanned() {
        let s = settings([act("Arabic", 60, days: [4])])
        #expect(!limits(s, done: [:], at: at(11)).needsNewRound(["Arabic"]))
    }

    @Test func restAloneDoesntStartARound() {
        let s = settings([act("Rest", 30)])
        #expect(!limits(s, done: ["Rest": 30], at: at(11)).needsNewRound(["Rest"]))
    }
}
