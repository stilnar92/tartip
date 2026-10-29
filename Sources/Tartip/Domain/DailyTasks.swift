import Foundation

struct ActivityTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var completed = false
}

// Activity IDs survive renaming. Dates keep yesterday's checklist out of today's plan.
struct DailyTasks: Codable, Equatable {
    var days: [String: [UUID: [ActivityTask]]] = [:]

    func tasks(day: String, activity: UUID) -> [ActivityTask] {
        days[day]?[activity] ?? []
    }

    mutating func set(_ tasks: [ActivityTask], day: String, activity: UUID) {
        days[day, default: [:]][activity] = tasks
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
