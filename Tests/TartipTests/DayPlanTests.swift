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

    @Test func theExampleRepeatsTask1InTheGap() {
        let w = wakingHours(example)
        let plan = planDay(example, weekday: monday, from: w.from, to: w.to)
        #expect(plan.first == PlanSlot(start: hm(9, 30), end: hm(10, 30), activity: "Task 1"))
        // Nothing else is open before 14:00, so Task 1 starts over until then.
        let gap = plan.filter { $0.start >= hm(10, 30) && $0.end <= hm(14) }
        #expect(gap.map(\.minutes).reduce(0, +) == hm(3, 30))
        #expect(gap.allSatisfy { $0.activity == "Task 1" && $0.round > 1 })
        // Task 2 and Task 3 still get their whole limit when they open.
        #expect(plan.contains { $0.activity == "Task 2" && $0.start == hm(14) && $0.minutes == 120 })
        #expect(plan.contains { $0.activity == "Task 3" && $0.start == hm(16) && $0.minutes == 180 })
        #expect(!plan.contains { $0.activity == nil })
        #expect(plan.last?.end == hm(21))
    }

    @Test func nothingOpenIsAGap() {
        let s = settings([act("Task 2", 120, 14, 21)])
        let plan = planDay(s, weekday: monday, from: hm(9, 30), to: hm(21))
        #expect(plan.first == PlanSlot(start: hm(9, 30), end: hm(14), activity: nil))
        #expect(plan[1].activity == "Task 2" && plan[1].round == 1 && plan[1].minutes == 120)
    }

    @Test func soonestClosingGoesFirst() {
        // Both open at 9:30; English closes at 11:00, so it can't wait.
        let s = settings([act("Work", 60), act("English", 30, 9, 11)])
        let plan = planDay(s, weekday: monday, from: hm(9, 30), to: hm(11))
        #expect(plan.first?.activity == "English")
        #expect(plan[1].activity == "Work")
    }

    @Test func restOnlyWhenNothingElse() {
        let s = settings([act("Rest", 30), act("Work", 60, 10, 21)])
        let plan = planDay(s, weekday: monday, from: hm(9, 30), to: hm(11))
        #expect(plan.first == PlanSlot(start: hm(9, 30), end: hm(10), activity: "Rest"))
        #expect(plan[1].activity == "Work" && plan[1].start == hm(10))
    }

    @Test func noLimitFillsBeforeARound() {
        let s = settings([act("Work", 60), act("Reading", 0)])
        let plan = planDay(s, weekday: monday, from: hm(10), to: hm(12))
        #expect(plan == [PlanSlot(start: hm(10), end: hm(11), activity: "Work"),
                         PlanSlot(start: hm(11), end: hm(12), activity: "Reading")])
    }

    @Test func otherWeekdaysAreLeftOut() {
        let s = settings([act("Arabic", 60, days: [4])])   // Wednesdays only
        #expect(planDay(s, weekday: monday, from: hm(10), to: hm(11)) == [PlanSlot(start: hm(10), end: hm(11), activity: nil)])
        #expect(planDay(s, weekday: 4, from: hm(10), to: hm(11)).first?.activity == "Arabic")
    }

    @Test func hoursCanCrossMidnight() {
        var s = settings([act("Late", 60, 23, 1)])
        s.nightEnabled = false
        let plan = planDay(s, weekday: monday, from: hm(22), to: hm(25))
        #expect(plan.contains { $0.activity == "Late" && $0.start == hm(23) && $0.minutes == 60 })
    }

    @Test func usedTimeCarriesIn() {
        let plan = planDay(example, weekday: monday, from: hm(9, 30), to: hm(10), used: ["Task 1": 45 * 60])
        #expect(plan.first == PlanSlot(start: hm(9, 30), end: hm(9, 45), activity: "Task 1"))
        #expect(plan[1].round == 2)
    }

    @Test func pastDayMergesAndMarksNoSession() {
        let done = [PlanSlot(start: hm(19, 24), end: hm(19, 39), activity: "Work", done: true),
                    PlanSlot(start: hm(18, 38), end: hm(18, 53), activity: "Project", done: true),
                    PlanSlot(start: hm(19, 9), end: hm(19, 24), activity: "Work", done: true)]
        #expect(pastDay(done, from: hm(8), until: hm(19, 41)) == [
            PlanSlot(start: hm(8), end: hm(18, 38), activity: nil, done: true),
            PlanSlot(start: hm(18, 38), end: hm(18, 53), activity: "Project", done: true),
            PlanSlot(start: hm(18, 53), end: hm(19, 9), activity: nil, done: true),
            PlanSlot(start: hm(19, 9), end: hm(19, 39), activity: "Work", done: true),
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
