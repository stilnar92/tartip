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
