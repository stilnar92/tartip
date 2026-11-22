import Foundation
import Testing
@testable import Tartip

// 2026-03-02 is a Monday; UTC so the weekday doesn't depend on the machine.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func day(_ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }
private let monday = day(2), saturday = day(7)

@Suite struct ScheduleTests {
    @Test func noDaysMeansEveryDay() {
        let a = ActivitySetting(name: "Work")
        #expect(a.isPlanned(on: monday, calendar: cal) && a.isPlanned(on: saturday, calendar: cal))
    }

    @Test func plannedOnlyOnItsDays() {
        var a = ActivitySetting(name: "Arabic")
        a.days = [2, 4, 6]                          // Mon, Wed, Fri
        #expect(a.isPlanned(on: monday, calendar: cal))
        #expect(!a.isPlanned(on: saturday, calendar: cal))
    }

    @Test func offDayActivitiesCantStartOrBeAutoPicked() {
        var s = AppSettings()
        var weekend = ActivitySetting(name: "Project"); weekend.days = [1, 7]
        s.activities = [ActivitySetting(name: "Work"), weekend]
        let mon = Limits(settings: s, today: [], now: monday, calendar: cal)
        #expect(mon.canStart("Work") && !mon.canStart("Project"))
        #expect(mon.autoPick(from: ["Project", "Work"]) == "Work")
        let sat = Limits(settings: s, today: [], now: saturday, calendar: cal)
        #expect(sat.canStart("Project"))
    }

    // The panel's "Nothing can start" and the away question share this: a day off or every
    // limit used up counts, not only a gap.
    @Test func nothingCanStartCoversDaysOffAndUsedLimits() {
        var s = AppSettings()
        var work = ActivitySetting(name: "Work"); work.dailyMinutes = 60
        var weekend = ActivitySetting(name: "Project"); weekend.days = [1, 7]
        s.activities = [work, weekend]
        let names = ["Work", "Project"]
        #expect(!Limits(settings: s, today: [], now: monday, calendar: cal).nothingCanStart(names))
        let hour = SessionRecord(start: monday.addingTimeInterval(-3600), end: monday, mode: "Work", planned: "Work")
        #expect(Limits(settings: s, today: [hour], now: monday, calendar: cal).nothingCanStart(names))
        #expect(!Limits(settings: s, today: [hour], now: monday, calendar: cal).nothingCanStart([]))
        // Saturday, nothing planned, a catch-up owed by weekday Work: still nothing to start.
        s.activities = [{ var w = work; w.days = [2, 3, 4, 5, 6]; w.catchUpMinutes = 30; return w }()]
        s.features.enabled.insert(.catchUp)
        let debt = CatchUpDebt(activity: "Work", day: "2026-03-06", windowEnd: day(6, 18), catchUpMinutes: 30)
        #expect(Limits(settings: s, today: [], now: saturday, calendar: cal, debts: [debt]).canStart("Work"))   // the old check said "can start"
        #expect(Limits(settings: s, today: [], now: saturday, calendar: cal, debts: [debt]).nothingCanStart(["Work"]))
    }

    // Dragging on the Plan timeline: only that weekday changes, back to usual drops the override.
    @Test func movingAWindowChangesOnlyThatWeekday() {
        var a = ActivitySetting(name: "Go", windows: [TimeWindow(from: 630, to: 720), TimeWindow(from: 870, to: 960)])
        let r1 = a.moveWindow(0, onWeekday: 2, from: 660, to: 750)
        #expect(r1)
        #expect(a.windows(onWeekday: 2).map(\.from) == [660, 870])
        #expect(a.windows(onWeekday: 3).map(\.from) == [630, 870])          // Tuesday untouched
        let r2 = a.moveWindow(0, onWeekday: 2, from: 840, to: 900)
        #expect(!r2)          // would overlap 14:30–16:00
        let r3 = a.moveWindow(0, onWeekday: 2, from: 630, to: 720)
        #expect(r3)
        #expect(a.dayWindows[2] == nil)                                      // same as usual again
        let r4 = a.moveWindow(1, onWeekday: 2, from: 1380, to: 1440)
        #expect(r4)         // to midnight
        #expect(a.windows(onWeekday: 2)[1].to == 0)
    }

    @Test func removingHoursKeepsOneAndTurningOffKeepsADay() {
        var a = ActivitySetting(name: "Go", windows: [TimeWindow(from: 630, to: 720), TimeWindow(from: 870, to: 960)])
        let r5 = a.removeWindow(0, onWeekday: 2)
        #expect(r5)
        #expect(a.windows(onWeekday: 2).count == 1 && a.windows.count == 2)
        let r6 = a.removeWindow(0, onWeekday: 2)
        #expect(!r6)                            // none left would mean any time
        let r7 = a.turnOff(onWeekday: 2)
        #expect(r7)
        #expect(!a.isPlanned(onWeekday: 2) && a.isPlanned(onWeekday: 3) && a.dayWindows[2] == nil)
        a.days = [3]
        let r8 = a.turnOff(onWeekday: 3)
        #expect(!r8)
    }

    @Test func deletingABlockTouchesOnlyThatWeekday() {
        var a = ActivitySetting(name: "Go", windows: [TimeWindow(from: 630, to: 720), TimeWindow(from: 870, to: 960)])
        let first = a.deleteWindow(1, onWeekday: 2)
        #expect(first && a.windows(onWeekday: 2).map(\.from) == [630] && a.windows(onWeekday: 3).count == 2)
        let last = a.deleteWindow(0, onWeekday: 2)                         // the day's last block: off that day
        #expect(last && !a.isPlanned(onWeekday: 2) && a.isPlanned(onWeekday: 3) && a.windows.count == 2)
    }

    @Test func overlapAcrossMidnight() {
        #expect(windowsOverlap(TimeWindow(from: 1380, to: 60), TimeWindow(from: 30, to: 120)))
        #expect(!windowsOverlap(TimeWindow(from: 600, to: 660), TimeWindow(from: 660, to: 720)))
    }

    @Test func daysLabels() {
        #expect(daysLabel([]) == "Every day")
        #expect(daysLabel([1, 2, 3, 4, 5, 6, 7]) == "Every day")
        #expect(daysLabel([2, 3, 4, 5, 6]) == "Weekdays")
        #expect(daysLabel([7, 1]) == "Weekends")
        #expect(daysLabel([2, 3, 4, 5]) == "Mon–Thu")
        #expect(daysLabel([6, 2, 4]) == "Mon, Wed, Fri")
        #expect(daysLabel([6, 7, 1]) == "Fri–Sun")
    }

    @Test func oldSettingsWithoutDaysStillLoad() throws {
        let json = #"{"name": "Work"}"#
        let a = try JSONDecoder().decode(ActivitySetting.self, from: Data(json.utf8))
        #expect(a.days.isEmpty)
    }

    @Test func ownLimitOnSomeDays() {
        var s = AppSettings()
        var work = ActivitySetting(name: "Work", dailyMinutes: 240)
        work.dayMinutes = [7: 60, 1: 0]              // Sat 1h, Sun no limit
        s.activities = [work]
        #expect(Limits(settings: s, today: [], now: monday, calendar: cal).limitMinutes("Work") == 240)
        #expect(Limits(settings: s, today: [], now: saturday, calendar: cal).limitMinutes("Work") == 60)
        let sunday = Limits(settings: s, today: [], now: day(8), calendar: cal)
        #expect(sunday.limitMinutes("Work") == 0 && sunday.secondsLeftToday("Work") == nil)
    }

    @Test func dayLimitsSurviveSaving() throws {
        var a = ActivitySetting(name: "Work", dailyMinutes: 120)
        a.days = [2, 3, 7]
        a.dayMinutes = [7: 45]
        let back = try JSONDecoder().decode(ActivitySetting.self, from: JSONEncoder().encode(a))
        #expect(back.dayMinutes == [7: 45] && back.limit(onWeekday: 7) == 45 && back.limit(onWeekday: 2) == 120)
    }

    // Some days have their own hours: Saturday 10–12 instead of the usual 14–18, Sunday any time.
    @Test func ownHoursOnSomeDays() {
        var s = AppSettings()
        var work = ActivitySetting(name: "Work", windows: [TimeWindow(from: 14 * 60, to: 18 * 60)])
        work.dayWindows = [7: [TimeWindow(from: 10 * 60, to: 12 * 60)], 1: []]
        s.activities = [work]
        #expect(!Limits(settings: s, today: [], now: day(2, 11), calendar: cal).isOpen("Work"))
        #expect(Limits(settings: s, today: [], now: day(2, 15), calendar: cal).isOpen("Work"))
        #expect(Limits(settings: s, today: [], now: day(7, 11), calendar: cal).isOpen("Work"))
        let satAfternoon = Limits(settings: s, today: [], now: day(7, 15), calendar: cal)
        #expect(!satAfternoon.isOpen("Work") && satAfternoon.opensLabel("Work") == "from 10:00")
        #expect(Limits(settings: s, today: [], now: day(8, 7), calendar: cal).isOpen("Work"))
        #expect(availability(s, weekday: 7, from: 0, to: 1440).contains { $0.start == 600 && $0.end == 720 && $0.available == ["Work"] })
        #expect(availability(s, weekday: 1, from: 0, to: 1440) == [Period(start: 0, end: 1440, available: ["Work"])])
    }

    // Shortening one day's hours is caught like shortening the usual ones.
    @Test func shorterHoursOnOneDayLoosen() {
        var o = AppSettings()
        o.activities = [ActivitySetting(name: "Work", windows: [TimeWindow(from: 600, to: 1080)])]
        var n = o
        n.activities[0].dayWindows = [7: [TimeWindow(from: 600, to: 720)]]
        #expect(loosenings(from: o, to: n).contains("shorter hours for Work"))
        #expect(!loosenings(from: n, to: o).contains("shorter hours for Work"))
    }

    // Work 9–12 and 15:30–18 leaves 12–15:30 with nothing to start: a gap, free unless locked.
    @Test func gapsBetweenHours() {
        var s = AppSettings()
        s.features.enabled.remove(.night)
        s.activities = [ActivitySetting(name: "Work", windows: [TimeWindow(from: 540, to: 720), TimeWindow(from: 930, to: 1080)])]
        let list = gaps(s, weekday: 2)
        #expect(list.contains(Gap(from: 720, to: 930)))
        let g = currentGap(s, at: day(2, 13), calendar: cal)
        #expect(g?.gap == Gap(from: 720, to: 930) && g?.end == day(2, 15).addingTimeInterval(30 * 60))
        #expect(currentGap(s, at: day(2, 10), calendar: cal) == nil)
        s.activities[0].days = [3]                   // Monday is a day off: no gaps at all
        #expect(gaps(s, weekday: 2).isEmpty && currentGap(s, at: day(2, 13), calendar: cal) == nil)
    }

    // Away in a gap: nothing could start, so coming back doesn't ask what you did. Only the
    // part outside the gap counts toward the minimum.
    @Test func awayInAGapIsntAsked() {
        var s = AppSettings()
        s.features.enabled.remove(.night)
        s.awayAsk = .text
        s.activities = [ActivitySetting(name: "Work", windows: [TimeWindow(from: 540, to: 720), TimeWindow(from: 930, to: 1080)])]
        let at = { (h: Int, m: Int) in day(2, h).addingTimeInterval(Double(m) * 60) }
        #expect(!s.asksAboutAway(since: at(12, 30), back: at(14, 0), calendar: cal))    // all in the 12–15:30 gap
        #expect(!s.asksAboutAway(since: at(11, 58), back: at(13, 0), calendar: cal))    // 2 min before it
        #expect(!s.asksAboutAway(since: at(15, 0), back: at(15, 33), calendar: cal))    // 3 min after it
        #expect(s.asksAboutAway(since: at(11, 50), back: at(13, 0), calendar: cal))     // 10 min before it
        #expect(s.asksAboutAway(since: at(10, 0), back: at(10, 30), calendar: cal))     // no gap at all
    }

    @Test func freeingALockedGapLoosens() {
        var o = AppSettings()
        o.lockedGaps = [Gap(from: 720, to: 930)]
        #expect(loosenings(from: o, to: AppSettings()).contains("freeing a gap"))
        #expect(!loosenings(from: AppSettings(), to: o).contains("freeing a gap"))
    }

    @Test func dayHoursSurviveSaving() throws {
        var a = ActivitySetting(name: "Work", windows: [TimeWindow(from: 600, to: 720)])
        a.dayWindows = [7: [TimeWindow(from: 900, to: 960)], 1: []]
        let back = try JSONDecoder().decode(ActivitySetting.self, from: JSONEncoder().encode(a))
        #expect(back.dayWindows == a.dayWindows && back.windows(onWeekday: 2) == a.windows && back.windows(onWeekday: 1).isEmpty)
    }

    // days and multiple windows are orthogonal: an off day has no periods at all for it,
    // regardless of how many windows it has on its planned days.
    @Test func multipleWindowsRespectDays() {
        var weekdayOnly = ActivitySetting(name: "Work", windows: [TimeWindow(from: 10 * 60, to: 12 * 60), TimeWindow(from: 16 * 60, to: 18 * 60)])
        weekdayOnly.days = [2, 3, 4, 5, 6]   // Mon-Fri
        var s = AppSettings()
        s.activities = [weekdayOnly]
        #expect(availability(s, weekday: 2, from: 0, to: 1440).contains { $0.available == ["Work"] })
        #expect(availability(s, weekday: 7, from: 0, to: 1440).allSatisfy { $0.available.isEmpty })   // Saturday
    }

    // Editing one window can't cross into a same-day neighbour: it clamps at the boundary,
    // touching exactly (no gap) is allowed.
    @Test func windowEditsClampAtNeighboringWindows() {
        let windows = [TimeWindow(from: 10 * 60, to: 12 * 60), TimeWindow(from: 16 * 60, to: 18 * 60)]
        // Pushing window 0's `to` past window 1's `from` clamps to exactly window 1's `from`.
        #expect(clampedWindowEdge(windows, editing: 0, movingFrom: false, to: 17 * 60) == 16 * 60)
        // Pushing window 1's `from` before window 0's `to` clamps to exactly window 0's `to`.
        #expect(clampedWindowEdge(windows, editing: 1, movingFrom: true, to: 11 * 60) == 12 * 60)
        // Touching exactly at the boundary is fine, left alone.
        #expect(clampedWindowEdge(windows, editing: 0, movingFrom: false, to: 16 * 60) == 16 * 60)
        // A value already clear of any neighbour passes through unchanged.
        #expect(clampedWindowEdge(windows, editing: 0, movingFrom: false, to: 11 * 60) == 11 * 60)
    }
}
