import Foundation

struct ActivityTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var completed = false
    var area: UUID? = nil   // the daily area it was planned under, if any
}

// Something you do for an activity every day, whose specifics change: "Solve a problem on
// bigfrontend.dev" under Interview, with today's "Curry" and "React task" as tasks under it.
// It's written once and shows up every day; each day it can be checked off on its own.
struct DailyArea: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
}

// Activity IDs survive renaming. Dates keep yesterday's checklist out of today's plan.
struct DailyTasks: Codable, Equatable {
    var days: [String: [UUID: [ActivityTask]]] = [:]
    var areas: [UUID: [DailyArea]] = [:]     // by activity, every day
    var areasDone: [String: [UUID]] = [:]    // by day: areas checked off by hand

    init() {}

    // Saved before daily areas existed: only `days`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String: [UUID: [ActivityTask]]].self, forKey: .days) ?? [:]
        areas = try c.decodeIfPresent([UUID: [DailyArea]].self, forKey: .areas) ?? [:]
        areasDone = try c.decodeIfPresent([String: [UUID]].self, forKey: .areasDone) ?? [:]
    }

    func tasks(day: String, activity: UUID) -> [ActivityTask] {
        days[day]?[activity] ?? []
    }

    func areas(for activity: UUID) -> [DailyArea] { areas[activity] ?? [] }

    mutating func setAreas(_ list: [DailyArea], for activity: UUID) { areas[activity] = list.isEmpty ? nil : list }

    // Done for the day: checked off by hand, or every one of today's tasks under it is done.
    func isDone(area: UUID, activity: UUID, day: String) -> Bool {
        if areasDone[day]?.contains(area) == true { return true }
        let items = tasks(day: day, activity: activity).filter { $0.area == area }
        return !items.isEmpty && items.allSatisfy(\.completed)
    }

    // Unchecking one that's done through its tasks reopens them: otherwise it couldn't be unchecked.
    mutating func toggle(area: UUID, activity: UUID, day: String) {
        if isDone(area: area, activity: activity, day: day) {
            areasDone[day]?.removeAll { $0 == area }
            if areasDone[day]?.isEmpty == true { areasDone[day] = nil }
            set(tasks(day: day, activity: activity).map { var t = $0; if t.area == area { t.completed = false }; return t },
                day: day, activity: activity)
        } else {
            areasDone[day, default: []].append(area)
        }
    }

    // Removing an area keeps its tasks, as plain tasks of the activity.
    mutating func removeArea(_ area: UUID, activity: UUID) {
        setAreas(areas(for: activity).filter { $0.id != area }, for: activity)
        for day in days.keys {
            let list = tasks(day: day, activity: activity)
            if list.contains(where: { $0.area == area }) {
                set(list.map { var t = $0; if t.area == area { t.area = nil }; return t }, day: day, activity: activity)
            }
        }
    }

    mutating func set(_ tasks: [ActivityTask], day: String, activity: UUID) {
        days[day, default: [:]][activity] = tasks
    }

    // Unfinished tasks planned for an earlier day, oldest day first. Nothing rolls over on its
    // own: they wait here until moved to today or deleted.
    func overdue(before today: String) -> [(day: String, activity: UUID, task: ActivityTask)] {
        days.keys.filter { $0 < today }.sorted().flatMap { day in
            (days[day] ?? [:]).sorted { $0.key.uuidString < $1.key.uuidString }.flatMap { activity, list in
                list.filter { !$0.completed }.map { (day, activity, $0) }
            }
        }
    }

    // Takes a task out of one day/activity and appends it to another, keeping its identity.
    mutating func move(_ id: UUID, from day: String, activity: UUID, to newDay: String, activity newActivity: UUID) {
        var list = tasks(day: day, activity: activity)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        var task = list.remove(at: index)
        if newActivity != activity { task.area = nil }   // areas belong to one activity
        set(list, day: day, activity: activity)
        set(tasks(day: newDay, activity: newActivity) + [task], day: newDay, activity: newActivity)
    }

    // Drag and drop: puts a task under another day/activity/area, just before another task (or
    // at the end). Dropped into another activity, an area must belong to that activity.
    mutating func place(_ id: UUID, from day: String, activity: UUID, to newDay: String, activity newActivity: UUID,
                        area: UUID?, before target: UUID?) {
        var source = tasks(day: day, activity: activity)
        guard let index = source.firstIndex(where: { $0.id == id }), id != target else { return }
        var task = source.remove(at: index)
        set(source, day: day, activity: activity)
        task.area = area.flatMap { a in areas(for: newActivity).contains { $0.id == a } ? a : nil }
        var dest = tasks(day: newDay, activity: newActivity)
        dest.insert(task, at: target.flatMap { t in dest.firstIndex { $0.id == t } } ?? dest.count)
        set(dest, day: newDay, activity: newActivity)
    }

    static func entries(_ text: String) -> [ActivityTask] {
        text.components(separatedBy: .newlines).compactMap {
            let title = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : ActivityTask(title: title)
        }
    }
}

// A session keeps a snapshot so later task edits do not rewrite what was reported.
struct CompletedTask: Codable, Equatable {
    var activity: String
    var taskID: UUID?
    var title: String
    var day: String
}

extension DailyTasks {
    mutating func complete(day: String, activities: [ActivitySetting], actual: [String],
                           selected: Set<UUID>, otherWork: [String: String]) -> [CompletedTask] {
        var completed: [CompletedTask] = []
        for name in actual {
            if let activity = activities.first(where: { $0.name == name }) {
                var list = tasks(day: day, activity: activity.id)
                for index in list.indices where selected.contains(list[index].id) && !list[index].completed {
                    list[index].completed = true
                    completed.append(CompletedTask(activity: name, taskID: list[index].id, title: list[index].title, day: day))
                }
                set(list, day: day, activity: activity.id)
            }
            let text = (otherWork[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { completed.append(CompletedTask(activity: name, title: text, day: day)) }
        }
        return completed
    }
}
