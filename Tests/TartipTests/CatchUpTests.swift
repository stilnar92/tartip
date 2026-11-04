import Foundation
import Testing
@testable import Tartip

// 2026-03-02 is a Monday; UTC so the weekday doesn't depend on the machine.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func day(_ d: Int, _ h: Int = 12, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h, minute: m))!
}
// `catchUp` is the minimum minutes English needs across the whole day; falling short by any
// amount creates a debt for exactly the shortfall.
private func english(_ catchUp: Int = 20) -> ActivitySetting {
    var a = ActivitySetting(name: "English", fromMinute: 9 * 60, toMinute: 11 * 60)
    a.catchUpMinutes = catchUp
    return a
}

// Two windows the same day: 09:00-11:00 and 16:00-18:00.
private func twoWindowEnglish(_ catchUp: Int = 20) -> ActivitySetting {
    var a = ActivitySetting(name: "English", windows: [TimeWindow(from: 9 * 60, to: 11 * 60), TimeWindow(from: 16 * 60, to: 18 * 60)])
    a.catchUpMinutes = catchUp
    return a
}
private func record(_ activity: String, _ start: Date, _ end: Date, actual: [String]? = nil) -> SessionRecord {
    SessionRecord(start: start, end: end, mode: activity, planned: activity, actual: actual ?? [])
}

// missedWindows looks back one calendar day, so isolate assertions to "today's" (day 2) entry
// unless a test is specifically about the lookback.
private func todays(_ missed: [(activity: String, day: String, windowEnd: Date, shortfall: Int)]) -> [(activity: String, day: String, windowEnd: Date, shortfall: Int)] {
    missed.filter { $0.day == "2026-03-02" }
}

@Suite struct CatchUpTests {
    @Test func openWindowIsNeverMissed() {
        let s = AppSettings(activities: [english()])
        // Window is 09:00-11:00; at 10:00 it hasn't closed yet.
        #expect(todays(missedWindows(s, records: [], now: day(2, 10), calendar: cal)).isEmpty)
    }

    @Test func closedWindowWithNothingDoneIsMissedForTheFullMinimum() {
        let s = AppSettings(activities: [english(20)])
        let missed = todays(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal))
        #expect(missed.count == 1 && missed[0].activity == "English" && missed[0].shortfall == 20)
    }

    @Test func closedWindowFullyCoveredByActualIsNotMissed() {
        let s = AppSettings(activities: [english(20)])
        let r = record("English", day(2, 9, 30), day(2, 10), actual: ["English"])   // 30 min >= 20 min minimum
        #expect(todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // Doing SOME of the minimum, but not all, creates a debt for only the shortfall.
    @Test func partialTimeCreatesADebtForTheShortfallOnly() {
        let s = AppSettings(activities: [english(20)])
        let r = record("English", day(2, 9), day(2, 9, 10), actual: ["English"])   // 10 of the 20 minutes needed
        let missed = todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal))
        #expect(missed.count == 1 && missed[0].shortfall == 10)
    }

    // A session still running across the window's close, or finished but not yet reviewed, is
    // visible only under `planned` (never `actual`) — it counts toward the day's sum either way
    // (secondsByActivity falls back to `planned` when `actual` is empty), so it isn't a shortfall
    // as long as its length alone already meets the minimum.
    @Test func stillRunningOrUnreviewedSessionCountsTowardTheMinimum() {
        let s = AppSettings(activities: [english(20)])
        let running = record("English", day(2, 10, 50), day(2, 11, 20))   // 30 min, planned=English, actual=[] (unreviewed)
        #expect(todays(missedWindows(s, records: [running], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // A session that ran during the window but was reviewed as a DIFFERENT activity doesn't
    // count toward English's sum at all — the full minimum is still owed.
    @Test func sessionReviewedAsSomethingElseDoesNotCount() {
        let s = AppSettings(activities: [english(20)])
        let r = record("English", day(2, 9), day(2, 10), actual: ["Reading"])
        let missed = todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal))
        #expect(missed.count == 1 && missed[0].activity == "English" && missed[0].shortfall == 20)
    }

    @Test func activityWithoutCatchUpMinutesIsNeverTracked() {
        let s = AppSettings(activities: [english(0)])
        #expect(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal).isEmpty)
    }

    @Test func notPlannedThatWeekdayIsNeverMissed() {
        var a = english()
        a.days = [7, 1]   // weekends only; Monday (day 2) is a weekday, so it must not appear.
        let s = AppSettings(activities: [a])
        #expect(todays(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // Reaching the minimum in ANY window clears the whole day: the sum is per activity per day,
    // not per window.
    @Test func reachingTheMinimumInOneOfTwoWindowsClearsTheWholeDay() {
        let s = AppSettings(activities: [twoWindowEnglish(20)])
        let r = record("English", day(2, 9, 30), day(2, 9, 50), actual: ["English"])   // 20 min, only the morning window
        #expect(todays(missedWindows(s, records: [r], now: day(2, 18, 1), calendar: cal)).isEmpty)
    }

    // Missing both windows entirely produces exactly one debt for the day, keyed to the LAST
    // window's end, for the full minimum (nothing was done anywhere).
    @Test func missingBothWindowsProducesOneDebtAtTheLastWindowsEnd() {
        let s = AppSettings(activities: [twoWindowEnglish(20)])
        let missed = todays(missedWindows(s, records: [], now: day(2, 18, 1), calendar: cal))
        #expect(missed.count == 1)
        #expect(missed[0].windowEnd == day(2, 18))
        #expect(missed[0].shortfall == 20)
    }

    // Seconds of timing slack never force a catch-up: a shortfall under a minute is no debt.
    @Test func shortfallUnderAMinuteIsIgnored() {
        let s = AppSettings(activities: [english(20)])
        let r = record("English", day(2, 9), day(2, 9, 19).addingTimeInterval(59), actual: ["English"])   // 19m59s of 20m
        #expect(todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // Yesterday is judged on its whole calendar day: a morning session still counts late the
    // next evening, as long as records reach back to yesterday's midnight.
    @Test func yesterdaysMorningStillCountsLateTheNextDay() {
        let s = AppSettings(activities: [english(20)])
        let morning = record("English", day(1, 9), day(1, 9, 30), actual: ["English"])
        let yesterday = missedWindows(s, records: [morning], now: day(2, 20), calendar: cal).filter { $0.day == "2026-03-01" }
        #expect(yesterday.isEmpty)
    }

    // A session that's running, paused while away, or waiting for its review isn't final yet:
    // debts must not be judged until it's done.
    @Test func openSessionsHoldOffTheDebtCheck() {
        let s = Session(block: "English", phases: [Phase(isBreak: false, minutes: 30)], start: day(2, 19, 39), planned: "English")
        let r = record("English", day(2, 19, 39), day(2, 20, 9))
        #expect(AppPhase.session(s).hasOpenSession)
        #expect(AppPhase.reviewing(r).hasOpenSession)
        #expect(AppPhase.away(since: day(2, 19, 44), paused: s).hasOpenSession)
        #expect(!AppPhase.away(since: day(2, 19, 44), paused: nil).hasOpenSession)
        #expect(!AppPhase.idle.hasOpenSession && !AppPhase.picking.hasOpenSession)
    }

    // The day's debt isn't created until the LAST window has closed, even if the first already has.
    @Test func noDebtUntilTheLastWindowOfTheDayCloses() {
        let s = AppSettings(activities: [twoWindowEnglish()])
        // 11:30: the morning window (09-11) is closed and missed, but the evening one (16-18) is still ahead.
        #expect(todays(missedWindows(s, records: [], now: day(2, 11, 30), calendar: cal)).isEmpty)
    }

    // Editing an activity's hours mid-day (e.g. adding/moving a window) after a debt already
    // exists must update that debt's windowEnd in place, never open a second debt for the same
    // (activity, day) — this is the identity recomputeDebts relies on to stay idempotent.
    @Test func sameActivityAndDayNeverGetsTwoDebts() {
        let existing = CatchUpDebt(activity: "Interview", day: "2026-11-02", windowEnd: day(2, 12), catchUpMinutes: 90)
        var debts = [existing]
        // Settings changed mid-day: missedWindows now reports a later windowEnd for the same (activity, day).
        let i = debts.firstIndex { $0.activity == "Interview" && $0.day == "2026-11-02" }!
        if debts[i].settledAt == nil { debts[i].windowEnd = day(2, 15, 30) }
        #expect(debts.count == 1)
        #expect(debts[0].windowEnd == day(2, 15, 30))
    }

    // Oldest unsettled debt wins; a tie on windowEnd is broken by the activities' list order.
    @Test func owedDebtIsOldestFirstThenListOrder() {
        let earlier = CatchUpDebt(activity: "Reading", day: "2026-03-01", windowEnd: day(1, 10), catchUpMinutes: 15)
        let later = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        #expect(owedDebt([later, earlier], order: ["English", "Reading"])?.activity == "Reading")

        let tieA = CatchUpDebt(activity: "Reading", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 15)
        let tieB = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        #expect(owedDebt([tieA, tieB], order: ["English", "Reading"])?.activity == "English")
    }

    @Test func settledOrExpiredDebtsAreNeverOwed() {
        let settled = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20, settledAt: day(2, 12))
        let expired = CatchUpDebt(activity: "Reading", day: "2026-03-01", windowEnd: day(1, 10), catchUpMinutes: 15, expired: true)
        #expect(owedDebt([settled, expired], order: ["English", "Reading"]) == nil)
    }

    // A debt only gates the activity it's owed by; every other activity is untouched.
    @Test func debtForcesOnlyItsOwnActivity() {
        var s = AppSettings(features: .legacy, activities: [english(), ActivitySetting(name: "Work")])
        s.features.enabled.insert(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.canStart("English") && !limits.canStart("Work"))
    }

    // A debt for an activity since deleted from Settings is orphaned (moot), not an eternal lock.
    @Test func orphanedDebtFallsThroughToNormalRules() {
        var s = AppSettings(features: .legacy, activities: [ActivitySetting(name: "Work")])
        s.features.enabled.insert(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.canStart("Work"))
    }

    // Catch-up is opt-in (Feature.catchUp): with the feature off, an existing debt must never
    // gate anything — the whole mechanism is inert, not just quieter.
    @Test func featureOffIgnoresExistingDebts() {
        var s = AppSettings(features: .legacy, activities: [english(), ActivitySetting(name: "Work")])
        s.features.enabled.remove(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.owedDebt == nil)
        #expect(limits.canStart("Work"))
    }

    // A catch-up that runs its full length settles the debt.
    @Test func fullCatchUpSettles() {
        var debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        var r = record("English", day(2, 12), day(2, 12, 20))
        r.ended = "done"
        pay(&debt, with: r, at: day(2, 12, 20))
        #expect(debt.settledAt == day(2, 12, 20))
    }

    // Ended early: the debt shrinks by the minutes done and stays owed, so End session
    // can't be used to skip a catch-up.
    @Test func endedEarlyCatchUpPaysOnlyItsMinutes() {
        var debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        var r = record("English", day(2, 12), day(2, 12, 5))
        r.ended = "stopped"
        pay(&debt, with: r, at: day(2, 12, 5))
        #expect(debt.settledAt == nil && debt.catchUpMinutes == 15)
        var rest = record("English", day(2, 13), day(2, 13, 15))
        rest.ended = "stopped"
        pay(&debt, with: rest, at: day(2, 13, 15))
        #expect(debt.settledAt == day(2, 13, 15))
    }

    // Ended early and reviewed as something else: none of it was the catch-up.
    @Test func endedEarlyCatchUpSpentOnOtherWorkPaysNothing() {
        var debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        var r = record("English", day(2, 12), day(2, 12, 10), actual: ["Work"])
        r.ended = "stopped"
        pay(&debt, with: r, at: day(2, 12, 10))
        #expect(debt.settledAt == nil && debt.catchUpMinutes == 20)
    }
}
