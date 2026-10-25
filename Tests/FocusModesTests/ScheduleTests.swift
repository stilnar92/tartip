import Foundation
import Testing
@testable import FocusModes

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
}
