import SwiftUI

// Task creation lives here so neither choosing nor doing an activity becomes an editing flow.
struct TaskPlanningView: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock
    @ObservedObject private var settings = Settings.shared

    private var orderedActivities: [ActivitySetting] {
        let activities = settings.value.activities.filter { !$0.name.isEmpty }
        guard let name = model.session?.planned,
              let current = activities.first(where: { $0.name == name }) else { return activities }
        return [current] + activities.filter { $0.id != current.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Tasks", subtitle: "Plan and check off today's work by activity.")
            Text(Fmt.dayTitle.string(from: clock.now))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
            if settings.value.activities.isEmpty {
                Text("Add an activity in Activities to start planning tasks.")
                    .foregroundStyle(Theme.text2)
            }
            ForEach(orderedActivities) { activity in
                VStack(alignment: .leading, spacing: 12) {
                    Label(activity.name, systemImage: ActivityStyle.of(activity).icon)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    DailyTaskEditor(model: model, clock: clock, activity: activity.id, initiallyExpanded: true)
                }
                .padding(16)
                .card(radius: 14)
            }
            Text("Saved automatically · each day has its own tasks")
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
    }
}

// Before starting, tasks are a reminder only. They cannot be edited or checked here.
struct DailyTaskPreview: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock
    let activity: UUID
    @State private var expanded = false

    var body: some View {
        let tasks = model.tasks(for: activity, day: dayKey(clock.now))
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        Text("Today's tasks")
                        Spacer()
                        Text("\(tasks.filter(\.completed).count)/\(tasks.count)")
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(tasks) { task in
                                Label(task.title, systemImage: task.completed ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                                    .strikethrough(task.completed)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
    }
}
