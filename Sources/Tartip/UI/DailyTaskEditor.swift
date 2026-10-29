import SwiftUI

struct DailyTaskEditor: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock
    let activity: UUID
    var initiallyExpanded = false
    @State private var expanded = false

    var body: some View {
        let day = dayKey(clock.now)
        let tasks = model.tasks(for: activity, day: day)
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text("Today's tasks")
                    Spacer()
                    if !tasks.isEmpty {
                        Text("\(tasks.filter(\.completed).count)/\(tasks.count)").monospacedDigit()
                    } else { Image(systemName: "plus") }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today's tasks, \(tasks.filter(\.completed).count) of \(tasks.count) completed")
            if expanded {
                TaskChecklist(model: model, activity: activity, day: day)
                    .id(day)
            }
        }
        .onAppear { expanded = initiallyExpanded }
    }
}

private struct TaskChecklist: View {
    @ObservedObject var model: Model
    let activity: UUID
    let day: String
    @State private var draft = ""
    @FocusState private var focus: UUID?
    private let newTask = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private var tasks: [ActivityTask] { model.tasks(for: activity, day: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tasks.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(tasks) { task in taskRow(task) }
                    }
                }
                .frame(maxHeight: 180)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(Theme.accent)
                TextField("Add a task…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: newTask)
                    .onSubmit(add)
                    .onChange(of: draft) { value in
                        if value.contains(where: \.isNewline) { add() }
                    }
                Button(action: add) { Image(systemName: "arrow.turn.down.left") }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add task (Return)")
                    .accessibilityLabel("Add task")
            }
            .font(.system(size: 13))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.pill.opacity(0.6)))
            Text("Return to add · paste multiple lines")
                .font(.system(size: 10)).foregroundStyle(Theme.text2)
        }
        .onDisappear { saveDraft() }
    }

    private func taskRow(_ task: ActivityTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { update(task.id) { $0.completed.toggle() } } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? Theme.accent : Theme.text2)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.completed ? "Mark incomplete: \(task.title)" : "Complete: \(task.title)")
            TextField("Task", text: Binding(
                get: { tasks.first { $0.id == task.id }?.title ?? "" },
                set: { value in update(task.id) { $0.title = value } }))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(task.completed ? Theme.text2 : Theme.text)
                .strikethrough(task.completed)
                .focused($focus, equals: task.id)
                .onSubmit { focus = newTask }
            Menu {
                Button("Move up") { move(task.id, by: -1) }
                    .disabled(tasks.first?.id == task.id)
                Button("Move down") { move(task.id, by: 1) }
                    .disabled(tasks.last?.id == task.id)
                Divider()
                Button("Delete task", role: .destructive) {
                    save(tasks.filter { $0.id != task.id })
                }
            } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.text2) }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Task actions: \(task.title)")
        }
        .padding(.vertical, 3)
    }

    private func save(_ value: [ActivityTask]) { model.setTasks(value, for: activity, day: day) }

    private func saveDraft() {
        let entries = DailyTasks.entries(draft)
        guard !entries.isEmpty else { return }
        save(tasks + entries)
        draft = ""
    }

    private func add() { saveDraft(); focus = newTask }

    private func update(_ id: UUID, _ change: (inout ActivityTask) -> Void) {
        var value = tasks
        guard let index = value.firstIndex(where: { $0.id == id }) else { return }
        change(&value[index])
        save(value)
    }

    private func move(_ id: UUID, by offset: Int) {
        var value = tasks
        guard let index = value.firstIndex(where: { $0.id == id }), value.indices.contains(index + offset) else { return }
        value.swapAt(index, index + offset)
        save(value)
    }
}
