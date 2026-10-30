import SwiftUI

// MARK: - "What's next?" (forced when nothing runs) and the review after a session

// The same Today list as the panel, in its own window that stays on top.
struct ActivityPickerView: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(title: "What's next?",
                      subtitle: "Click an activity to start it, or take free time. Nothing is blocked until you choose.")
            // If nobody answers, an activity starts by itself; say which and when.
            if let at = model.autoStartAt, let activity = model.autoStartActivity {
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundStyle(Theme.accent)
                    Text("\(activity) starts by itself in \(countdown(to: at, from: clock.now)) for \(formatDuration(model.limits.sessionSeconds(activity, requested: max(Settings.current.minMinutes, Settings.current.autoStartMinutes) * 60)))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentTint))
            }
            TodayList(model: model, clock: clock, warnOnStart: false)
        }
        .padding(24)
        .frame(width: 420)
    }
}

// Activity selection and completion remain separate, with edits staged until Save.
struct ReviewView: View {
    @ObservedObject var model: Model
    var size = CGSize(width: 880, height: 660)
    @State private var picked: [String]? = nil
    @State private var selectedTasks: Set<UUID> = []
    @State private var otherWork: [String: String] = [:]

    private var checked: [String] { picked ?? (model.review?.planned.map { [$0] } ?? []) }
    private var day: String { dayKey(model.review?.began ?? model.review?.start ?? model.now) }
    private var names: [String] {
        var all = model.activities
        if let planned = model.review?.planned {
            all.removeAll { $0 == planned }
            all.insert(planned, at: 0)
        }
        if !all.contains(otherActivity) { all.append(otherActivity) }
        return all
    }
    private var selectedNames: [String] { names.filter { checked.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PageTitle(title: "Session done", subtitle: Settings.current.has(.tasks) ? "Choose what you worked on and mark the tasks you completed." : "Choose what you worked on.")
                Spacer(minLength: 16)
                Tag(text: "\((model.review?.seconds ?? 0) / 60) min", color: Theme.accent, fill: Theme.accentTint)
            }
            .padding(24)
            Divider()

            if !Settings.current.has(.tasks) {
                ScrollView { VStack { ForEach(names, id: \.self) { activityButton($0) } }.padding(24) }
            } else if size.width >= 700 {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Activities")
                        Text("Select one or more").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(names, id: \.self) { activityButton($0) }
                            }
                        }
                    }
                    .padding(18)
                    .frame(width: 240)
                    Divider()
                    taskPane
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Activities · select one or more")
                    ScrollView {
                        FlowLayout {
                            ForEach(names, id: \.self) { activityButton($0, compact: true) }
                        }
                    }
                    .frame(height: min(130, size.height * 0.22))
                }
                .padding(.horizontal, 20).padding(.top, 16)
                taskPane
            }

            Divider()
            HStack(spacing: 16) {
                Text(checked.isEmpty ? "Select an activity to continue" : "\(checked.count) \(checked.count == 1 ? "activity" : "activities") selected")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                Spacer()
                Button {
                    model.saveReview(actual: checked, selectedTasks: selectedTasks, otherWork: otherWork)
                } label: {
                    Text("Save review")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(checked.isEmpty).opacity(checked.isEmpty ? 0.4 : 1)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: size.width, height: size.height)
    }

    private func activityButton(_ name: String, compact: Bool = false) -> some View {
        let on = checked.contains(name)
        return Button {
            var selection = checked
            if let index = selection.firstIndex(of: name) { selection.remove(at: index) }
            else { selection.append(name) }
            picked = selection
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.accent : Theme.text2)
                Image(systemName: ActivityStyle.of(name).icon)
                    .foregroundStyle(ActivityStyle.of(name).color).frame(width: 18)
                Text(name).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Spacer(minLength: 0)
                    if name == model.review?.planned {
                        Image(systemName: "timer").foregroundStyle(Theme.text2).help("Planned activity")
                    }
                }
            }
            .font(.system(size: 13, weight: on ? .medium : .regular))
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(on ? Theme.accentTint : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(on ? "Deselect" : "Select") activity: \(name)")
    }

    private var taskPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Completed work")
            if selectedNames.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checklist").font(.system(size: 28))
                    Text("Select an activity to see its tasks.").font(.system(size: 14))
                }
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(selectedNames, id: \.self) { taskGroup($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func taskGroup(_ name: String) -> some View {
        let tasks = Settings.current.activity(named: name).map { model.tasks(for: $0.id, day: day) } ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(name, systemImage: ActivityStyle.of(name).icon)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if name == model.review?.planned { Tag(text: "planned") }
            }
            if tasks.isEmpty {
                Text("No tasks planned. You can still record this activity.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            ForEach(tasks) { task in
                Button {
                    if selectedTasks.contains(task.id) { selectedTasks.remove(task.id) }
                    else { selectedTasks.insert(task.id) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: task.completed || selectedTasks.contains(task.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(task.completed || selectedTasks.contains(task.id) ? Theme.accent : Theme.text2)
                        Text(task.title).foregroundStyle(task.completed ? Theme.text2 : Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if task.completed {
                            Text("Done earlier").foregroundStyle(Theme.text2).font(.system(size: 11))
                        }
                    }
                    .font(.system(size: 14)).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(task.completed)
            }
            TextField("Other work (optional)", text: Binding(get: { otherWork[name] ?? "" }, set: { otherWork[name] = $0 }))
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .accessibilityLabel("Other work for \(name)")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}
