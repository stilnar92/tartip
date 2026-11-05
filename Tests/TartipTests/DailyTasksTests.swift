import Foundation
import Testing
@testable import Tartip

@Suite struct DailyTasksTests {
    // Saved task lists from before daily areas still load, tasks intact.
    @Test func oldSavedTasksStillLoad() throws {
        let id = UUID()
        let json = #"{"days":{"2026-10-29":["\#(id.uuidString)",[{"id":"\#(UUID().uuidString)","title":"Old","completed":false}]]}}"#
        let book = try JSONDecoder().decode(DailyTasks.self, from: Data(json.utf8))
        #expect(book.tasks(day: "2026-10-29", activity: id).map(\.title) == ["Old"])
        #expect(book.areas.isEmpty && book.areasDone.isEmpty)
    }

    // An area is done for the day by hand or once all of that day's tasks under it are done,
    // and comes back unchecked the next day.
    @Test func areaDonePerDay() {
        let interview = UUID()
        var book = DailyTasks()
        let area = DailyArea(title: "bigfrontend.dev")
        book.setAreas([area], for: interview)
        #expect(!book.isDone(area: area.id, activity: interview, day: "2026-11-05"))
        book.toggle(area: area.id, activity: interview, day: "2026-11-05")
        #expect(book.isDone(area: area.id, activity: interview, day: "2026-11-05"))
        #expect(!book.isDone(area: area.id, activity: interview, day: "2026-11-06"))
        var items = DailyTasks.entries("Curry\nReact task").map { var t = $0; t.area = area.id; return t }
        items[0].completed = true; items[1].completed = true
        book.set(items, day: "2026-11-06", activity: interview)
        #expect(book.isDone(area: area.id, activity: interview, day: "2026-11-06"))
        book.toggle(area: area.id, activity: interview, day: "2026-11-06")   // unchecking reopens its tasks
        #expect(!book.isDone(area: area.id, activity: interview, day: "2026-11-06"))
        #expect(book.tasks(day: "2026-11-06", activity: interview).allSatisfy { !$0.completed })
    }

    @Test func droppingReordersAndMovesBetweenActivitiesAndAreas() {
        let work = UUID(), interview = UUID()
        var book = DailyTasks()
        let area = DailyArea(title: "bigfrontend.dev")
        book.setAreas([area], for: interview)
        let t = DailyTasks.entries("A\nB\nC")
        book.set(t, day: "2026-11-05", activity: work)
        book.place(t[2].id, from: "2026-11-05", activity: work, to: "2026-11-05", activity: work, area: nil, before: t[0].id)
        #expect(book.tasks(day: "2026-11-05", activity: work).map(\.title) == ["C", "A", "B"])
        // From an earlier day into another activity's area, at the end.
        book.set([ActivityTask(title: "Old")], day: "2026-11-01", activity: work)
        let old = book.tasks(day: "2026-11-01", activity: work)[0]
        book.place(old.id, from: "2026-11-01", activity: work, to: "2026-11-05", activity: interview, area: area.id, before: nil)
        #expect(book.tasks(day: "2026-11-01", activity: work).isEmpty)
        #expect(book.tasks(day: "2026-11-05", activity: interview).map(\.area) == [area.id])
        // An area from another activity doesn't come along.
        book.place(t[0].id, from: "2026-11-05", activity: work, to: "2026-11-05", activity: work, area: area.id, before: nil)
        #expect(book.tasks(day: "2026-11-05", activity: work).last?.area == nil)
    }

    @Test func removingAnAreaKeepsItsTasks() {
        let interview = UUID()
        var book = DailyTasks()
        let area = DailyArea(title: "bigfrontend.dev")
        book.setAreas([area], for: interview)
        book.set([ActivityTask(title: "Curry", area: area.id)], day: "2026-11-05", activity: interview)
        book.removeArea(area.id, activity: interview)
        #expect(book.areas(for: interview).isEmpty)
        #expect(book.tasks(day: "2026-11-05", activity: interview).map(\.area) == [nil])
    }

    @Test func overdueIsUnfinishedFromEarlierDaysOnly() {
        let work = UUID()
        var book = DailyTasks()
        var old = DailyTasks.entries("Done before\nStill open")
        old[0].completed = true
        book.set(old, day: "2026-10-28", activity: work)
        book.set(DailyTasks.entries("Today's"), day: "2026-10-30", activity: work)
        #expect(book.overdue(before: "2026-10-30").map(\.task.title) == ["Still open"])
        #expect(book.overdue(before: "2026-10-28").isEmpty)
    }

    @Test func movingKeepsTheTaskAndAppendsIt() {
        let work = UUID(), study = UUID()
        var book = DailyTasks()
        let old = DailyTasks.entries("Carry me\nStay")
        book.set(old, day: "2026-10-28", activity: work)
        book.set(DailyTasks.entries("First today"), day: "2026-10-30", activity: study)
        book.move(old[0].id, from: "2026-10-28", activity: work, to: "2026-10-30", activity: study)
        #expect(book.tasks(day: "2026-10-28", activity: work).map(\.title) == ["Stay"])
        #expect(book.tasks(day: "2026-10-30", activity: study).map(\.title) == ["First today", "Carry me"])
        #expect(book.tasks(day: "2026-10-30", activity: study).last?.id == old[0].id)
    }

    @Test func separatesDaysAndActivities() {
        let work = UUID(), study = UUID()
        var book = DailyTasks()
        let entries = DailyTasks.entries("Write proposal\n\n  Review changes  \r\nSend update")
        #expect(entries.map(\.title) == ["Write proposal", "Review changes", "Send update"])
        #expect(Set(entries.map(\.id)).count == 3)
        book.set(entries, day: "2026-10-29", activity: work)
        #expect(book.tasks(day: "2026-10-30", activity: work).isEmpty)
        #expect(book.tasks(day: "2026-10-29", activity: study).isEmpty)
        #expect(book.tasks(day: "2026-10-29", activity: work) == entries)
    }

    @Test func persistsIdentityCompletionAndOrder() throws {
        let defaults = UserDefaults(suiteName: "TartipTests.Tasks.\(UUID())")!
        let activity = UUID()
        var book = DailyTasks()
        var tasks = DailyTasks.entries("First\nSecond")
        tasks[0].completed = true
        tasks.swapAt(0, 1)
        book.set(tasks, day: "2026-10-29", activity: activity)
        DailyTaskStore.save(book, to: defaults)
        let restored = DailyTaskStore.load(from: defaults)
        #expect(restored == book)
        #expect(restored.tasks(day: "2026-10-29", activity: activity)[1].completed)
        // Task storage does not alter the existing saved session state.
        #expect(defaults.data(forKey: "state") == nil)
        defaults.removeObject(forKey: "dailyActivityTasks")
    }

    @Test func missingTaskStorageStartsEmpty() {
        let defaults = UserDefaults(suiteName: "TartipTests.Tasks.\(UUID())")!
        #expect(DailyTaskStore.load(from: defaults) == DailyTasks())
    }

    @Test func reviewCompletesOnlyTasksFromSelectedActivitiesAndDay() {
        let work = ActivitySetting(name: "Work"), study = ActivitySetting(name: "Study")
        let workTask = ActivityTask(title: "Proposal"), studyTask = ActivityTask(title: "Vocabulary")
        var book = DailyTasks()
        book.set([workTask], day: "2026-10-29", activity: work.id)
        book.set([studyTask], day: "2026-10-29", activity: study.id)
        book.set([workTask], day: "2026-10-30", activity: work.id)
        let result = book.complete(day: "2026-10-29", activities: [work, study], actual: ["Study"],
                                   selected: [workTask.id, studyTask.id],
                                   otherWork: ["Work": "Hidden work", "Study": "Reading"])
        #expect(result.map(\.title) == ["Vocabulary", "Reading"])
        #expect(result.allSatisfy { $0.activity == "Study" })
        #expect(!book.tasks(day: "2026-10-29", activity: work.id)[0].completed)
        #expect(!book.tasks(day: "2026-10-30", activity: work.id)[0].completed)
        #expect(book.tasks(day: "2026-10-29", activity: study.id)[0].completed)
    }

    @Test func reviewSupportsSeveralActivitiesAndOtherWorkWithoutRepeatingEarlierCompletions() {
        let work = ActivitySetting(name: "Work"), study = ActivitySetting(name: "Study")
        let first = ActivityTask(title: "First"), second = ActivityTask(title: "Second")
        var book = DailyTasks()
        book.set([first], day: "today", activity: work.id)
        book.set([second], day: "today", activity: study.id)
        let result = book.complete(day: "today", activities: [work, study], actual: ["Work", "Study", "Other"],
                                   selected: [first.id, second.id], otherWork: ["Other": "  Unexpected work  "])
        #expect(result.map(\.activity) == ["Work", "Study", "Other"])
        #expect(result.last?.title == "Unexpected work")
        #expect(result.last?.taskID == nil)
        #expect(book.complete(day: "today", activities: [work, study], actual: ["Work"],
                              selected: [first.id], otherWork: [:]).isEmpty)
    }

    @Test func sessionTaskSnapshotsRemainReadableAndOldRecordsStillDecode() throws {
        let old = Data(#"{"start":"2026-10-29T10:00:00Z","end":"2026-10-29T10:30:00Z","mode":"Work","actual":["Work"]}"#.utf8)
        var record = try recordDecoder().decode(SessionRecord.self, from: old)
        #expect(record.completedTasks == nil)
        record.completedTasks = [CompletedTask(activity: "Work", taskID: UUID(), title: "Original title", day: "2026-10-29")]
        let restored = try recordDecoder().decode(SessionRecord.self, from: recordEncoder().encode(record))
        #expect(restored == record)
    }
}
