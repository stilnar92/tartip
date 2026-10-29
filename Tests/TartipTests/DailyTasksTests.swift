import Foundation
import Testing
@testable import Tartip

@Suite struct DailyTasksTests {
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
