import Foundation
import Testing
@testable import Tartip

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func at(_ h: Int, _ m: Int = 0, day: Int = 2) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
}

@Suite struct SettingsLockTests {
    @Test func offNeverLocks() {
        #expect(LockSettings().lockedUntil(now: at(12), changedAt: at(11), calendar: cal) == nil)
    }

    @Test func afterChangeLocksAfterTheGraceForTheChosenTime() {
        var l = LockSettings(); l.mode = .afterChange; l.hours = 2
        let changed = at(10)
        #expect(l.lockedUntil(now: at(10, 5), changedAt: changed, calendar: cal) == nil)          // still finishing
        #expect(l.locksAt(changedAt: changed, now: at(10, 5)) == at(10, 10))
        #expect(l.lockedUntil(now: at(11), changedAt: changed, calendar: cal) == at(12, 10))
        #expect(l.lockedUntil(now: at(12, 10), changedAt: changed, calendar: cal) == nil)        // over
        #expect(!l.newRound(now: at(11), changedAt: changed))
        #expect(l.newRound(now: at(12, 30), changedAt: changed))
    }

    @Test func hoursLockOutsideTheWindow() {
        var l = LockSettings(); l.mode = .hours; l.from = 21 * 60; l.to = 21 * 60 + 30
        #expect(l.lockedUntil(now: at(21, 10), changedAt: nil, calendar: cal) == nil)
        #expect(l.lockedUntil(now: at(15), changedAt: nil, calendar: cal) == at(21))
        #expect(l.lockedUntil(now: at(22), changedAt: nil, calendar: cal) == at(21, day: 3))
        // Just switched on: a few minutes to set the hours.
        #expect(l.lockedUntil(now: at(15, 5), changedAt: at(15), calendar: cal) == nil)
    }

    @Test func looserChangesAreNamed() {
        var o = AppSettings()
        var work = ActivitySetting(name: "Work", dailyMinutes: 120); work.days = [2, 3, 4]
        o.activities = [work, ActivitySetting(name: "Rest")]
        o.lock.mode = .afterChange

        var n = o
        n.activities.removeAll { $0.name == "Rest" }
        n.activities[0].days = [2, 3]
        n.activities[0].dailyMinutes = 60
        n.dailyFreeMinutes += 30
        n.nightEnabled = false
        n.lock.mode = .off
        #expect(loosenings(from: o, to: n) == ["fewer days for Work", "a lower limit for Work", "removing Rest",
                                               "more free time", "turning night off", "turning the settings lock off"])
    }

    @Test func stricterChangesPass() {
        var o = AppSettings()
        var work = ActivitySetting(name: "Work", dailyMinutes: 120); work.days = [2, 3]
        o.activities = [work]
        o.lock.mode = .afterChange; o.lock.hours = 12

        var n = o
        n.activities[0].days = [2, 3, 4]                  // another day
        n.activities[0].dailyMinutes = 0                  // no limit: as long as it takes
        n.activities.append(ActivitySetting(name: "Study"))
        n.dailyFreeMinutes -= 30
        n.lock.hours = 48
        n.activities[0].icon = "brain"                    // looks don't matter
        #expect(loosenings(from: o, to: n).isEmpty)
    }
}
