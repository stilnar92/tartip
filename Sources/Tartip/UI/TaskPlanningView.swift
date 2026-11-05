import SwiftUI
import AppKit

// Today's tasks as one list, the way Todoist and TickTick do it: a quick-add bar on top that
// files the task under an activity, then the open tasks grouped by activity, anything left
// unfinished from earlier days as Overdue, and what's done tucked away at the bottom.
// Task creation lives here so neither choosing nor doing an activity becomes an editing flow.
struct TaskPlanningView: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock
    @ObservedObject private var settings = Settings.shared
    @State private var draft = ""
    @State private var target: UUID?          // the activity quick-add files under
    @State private var showsDone = false
    @State private var showsAllOverdue = false
    @State private var asksDeleteOverdue = false
    @State private var targetArea: UUID?      // and the daily area within it, if one was picked
    @State private var newAreaFor: UUID?      // activity whose "New daily area" field is open
    @State private var areaDraft = ""
    @State private var selected: UUID?        // the task the shortcuts act on: last clicked or edited
    @State private var dropArea: UUID?
    @StateObject private var keys = KeyMonitor()        // the area or activity header a task is dragged over
    @FocusState private var focus: TaskFocus?

    private var activities: [ActivitySetting] {
        let all = settings.value.activities.filter { !$0.name.isEmpty }
        guard let name = model.session?.planned, let current = all.first(where: { $0.name == name }) else { return all }
        return [current] + all.filter { $0.id != current.id }
    }
    private var today: String { dayKey(clock.now) }
    private var targetActivity: ActivitySetting? { activities.first { $0.id == target } ?? activities.first }
    private var weekday: Int { Calendar.current.component(.weekday, from: clock.now) }

    // An activity's section shows when it has open tasks today, or daily areas on a day it's planned.
    private func areas(_ a: ActivitySetting) -> [DailyArea] {
        a.isPlanned(onWeekday: weekday) || !model.tasks(for: a.id, day: today).isEmpty ? model.dailyTasks.areas(for: a.id) : []
    }

    var body: some View {
        let lists = activities.map { ($0, model.tasks(for: $0.id, day: today)) }
        let all = lists.flatMap(\.1)
        let allAreas = activities.flatMap { a in areas(a).map { (a, $0) } }
        let areasDone = allAreas.filter { model.dailyTasks.isDone(area: $0.1.id, activity: $0.0.id, day: today) }.count
        let done = all.filter(\.completed).count
        let known = Set(activities.map(\.id))
        let overdue = model.dailyTasks.overdue(before: today).filter { known.contains($0.activity) }

        return VStack(alignment: .leading, spacing: 18) {
            header(done: done + areasDone, total: all.count + allAreas.count)
            if activities.isEmpty {
                Text("Add an activity in Activities to start planning tasks.").foregroundStyle(Theme.text2)
            } else {
                quickAdd
                if !overdue.isEmpty { overdueSection(overdue) }
                let open = lists.filter { a, tasks in tasks.contains { !$0.completed } || !areas(a).isEmpty || newAreaFor == a.id }
                if open.isEmpty && overdue.isEmpty { emptyState(anyDone: done > 0) }
                ForEach(open, id: \.0.id) { activity, tasks in section(activity, tasks) }
                if done > 0 { doneSection(lists) }
                shortcutHints
            }
        }
        .onAppear { keys.start() }
        .onDisappear { keys.stop() }
        .background(keyHandler(rows(lists, overdue)))
    }

    // MARK: keyboard

    // Every row on screen, in order, with where it's stored: what the task shortcuts act on.
    private func rows(_ lists: [(ActivitySetting, [ActivityTask])],
                      _ overdue: [(day: String, activity: UUID, task: ActivityTask)]) -> [(id: UUID, day: String, activity: UUID)] {
        typealias Row = (id: UUID, day: String, activity: UUID)
        let shownOverdue = showsAllOverdue ? overdue : Array(overdue.prefix(5))
        var out: [Row] = shownOverdue.map { ($0.task.id, $0.day, $0.activity) }
        for (a, tasks) in lists {
            let list = areas(a)
            let ids = Set(list.map(\.id))
            let byArea: [ActivityTask] = list.flatMap { area in tasks.filter { !$0.completed && $0.area == area.id } }
            let loose: [ActivityTask] = tasks.filter { t in !t.completed && !(t.area.map { ids.contains($0) } ?? false) }
            out += (byArea + loose).map { ($0.id, today, a.id) }
        }
        if showsDone {
            for (a, tasks) in lists { out += tasks.filter(\.completed).map { ($0.id, today, a.id) } }
        }
        return out
    }

    // Keys are read straight off the window's key events while this page is open: SwiftUI's
    // .keyboardShortcut buttons only got ⌘N through, and nothing else, with a title being edited.
    // The task keys act on the selected task (clicked, or its title being edited).
    private func keyHandler(_ rows: [(id: UUID, day: String, activity: UUID)]) -> some View {
        keys.handler = { handleKey($0, rows) }
        return Color.clear.frame(width: 0, height: 0)
    }

    private func handleKey(_ e: NSEvent, _ rows: [(id: UUID, day: String, activity: UUID)]) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
        // Only in the main window (not "What's next?" or the review, which are panels).
        guard mods.contains(.command), !mods.contains(.control), !(e.window is NSPanel) else { return false }
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let current: (id: UUID, day: String, activity: UUID)? = {
            if case .task(let id) = focus, let r = rows.first(where: { $0.id == id }) { return r }
            if focus == .add { return nil }   // typing a new task: ⌘⌫ edits the text, not a task
            return selected.flatMap { id in rows.first { $0.id == id } }
        }()
        let list = current.map { model.tasks(for: $0.activity, day: $0.day) } ?? []
        func set(_ value: [ActivityTask]) { if let c = current { model.setTasks(value, for: c.activity, day: c.day) } }
        func step(_ offset: Int) {
            guard let c = current, let i = rows.firstIndex(where: { $0.id == c.id }), rows.indices.contains(i + offset) else { return }
            selected = rows[i + offset].id
            focus = .task(rows[i + offset].id)
        }
        func swap(_ offset: Int) {
            guard let c = current, let i = list.firstIndex(where: { $0.id == c.id }), list.indices.contains(i + offset) else { return }
            var v = list; v.swapAt(i, i + offset); set(v)
        }
        switch (e.keyCode, mods) {
        case (36, [.command]), (76, [.command]):                      // ⌘↩ done / not done
            guard let c = current else { return false }
            set(list.map { var t = $0; if t.id == c.id { t.completed.toggle() }; return t })
            step(1)
        case (51, [.command]), (117, [.command]):                     // ⌘⌫ delete
            guard let c = current, let i = rows.firstIndex(where: { $0.id == c.id }) else { return false }
            let next = rows.indices.contains(i + 1) ? rows[i + 1].id : rows.indices.contains(i - 1) ? rows[i - 1].id : nil
            set(list.filter { $0.id != c.id })
            selected = next
            focus = next.map { .task($0) } ?? .add
        case (126, [.command, .option]): swap(-1)                     // ⌥⌘↑ ⌥⌘↓ reorder
        case (125, [.command, .option]): swap(1)
        case (126, [.command]): step(-1)                              // ⌘↑ ⌘↓ previous / next
        case (125, [.command]): step(1)
        default:
            switch (key, mods) {
            case ("n", [.command]): focus = .add
            case ("t", [.command]):
                guard let c = current, c.day < today else { return false }
                model.moveTask(c.id, from: c.day, activity: c.activity, to: today, activity: c.activity)
            case ("d", [.command, .shift]): withAnimation(.snappy) { showsDone.toggle() }
            case (_, [.command]) where Int(key).map({ (1...9).contains($0) }) == true:
                guard let n = Int(key), activities.count >= n else { return false }
                target = activities[n - 1].id; targetArea = nil; focus = .add
            default: return false
            }
        }
        return true
    }

    private var shortcutHints: some View {
        let keys = [("⌘N", "new task"), ("⌘1–9", "pick activity"), ("⌘↩", "done"), ("⌘⌫", "delete"),
                    ("⌘↑ ⌘↓", "next/previous"), ("⌥⌘↑ ⌥⌘↓", "reorder"), ("⌘T", "overdue to today"), ("⇧⌘D", "show completed")]
        return FlowLayout(spacing: 10) {
            ForEach(keys, id: \.0) { k, what in
                HStack(spacing: 4) {
                    Text(k).font(.system(size: 10, weight: .semibold)).fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.pill))
                    Text(what).font(.system(size: 10)).fixedSize()
                }
                .foregroundStyle(Theme.text2)
            }
        }
        .padding(.top, 8)
    }

    // MARK: header

    private func header(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                PageTitle(title: "Today", subtitle: Fmt.dayTitle.string(from: clock.now))
                Spacer()
                if total > 0 {
                    Text("\(done) of \(total) done").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.text2)
                }
            }
            if total > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.pill)
                        Capsule().fill(Color.green).frame(width: g.size.width * CGFloat(done) / CGFloat(total))
                    }
                }
                .frame(height: 4)
                .animation(.snappy, value: done)
            }
        }
    }

    // MARK: quick add

    // Type, Return, keep typing: the field stays focused. Pasting several lines adds each.
    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($focus, equals: .add)
                .onSubmit(add)
                .onChange(of: draft) { value in if value.contains(where: \.isNewline) { add() } }
            if let a = targetActivity {
                let st = ActivityStyle.of(a)
                let area = model.dailyTasks.areas(for: a.id).first { $0.id == targetArea }
                Menu {
                    ForEach(activities) { other in
                        Button { target = other.id; targetArea = nil; focus = .add } label: {
                            Label(other.name, systemImage: ActivityStyle.of(other).icon)
                        }
                        ForEach(model.dailyTasks.areas(for: other.id)) { ar in
                            Button("      \(ar.title)") { target = other.id; targetArea = ar.id; focus = .add }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: st.icon).foregroundStyle(st.color)
                        Text(area.map { "\(a.name) › \($0.title)" } ?? a.name).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(st.color.opacity(0.12)))
                .help("The activity this task is for")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(focus == .add ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: focus == .add ? 1.5 : 1))
    }

    private func add() {
        let entries = DailyTasks.entries(draft)
        draft = ""
        guard !entries.isEmpty, let a = targetActivity else { return }
        let area = model.dailyTasks.areas(for: a.id).contains { $0.id == targetArea } ? targetArea : nil
        model.setTasks(model.tasks(for: a.id, day: today) + entries.map { var t = $0; t.area = area; return t }, for: a.id, day: today)
        focus = .add
    }

    // MARK: sections

    // Daily areas first, each with today's tasks under it, then the activity's other tasks.
    private func section(_ activity: ActivitySetting, _ tasks: [ActivityTask]) -> some View {
        let st = ActivityStyle.of(activity)
        let list = areas(activity)
        let ids = Set(list.map(\.id))
        let loose = tasks.filter { !$0.completed && !($0.area.map(ids.contains) ?? false) }
        let areasDone = list.filter { model.dailyTasks.isDone(area: $0.id, activity: activity.id, day: today) }.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: st.icon).font(.system(size: 12)).foregroundStyle(st.color)
                Text(activity.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(tasks.filter(\.completed).count + areasDone)/\(tasks.count + list.count)")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                Spacer()
                Menu {
                    Button("Add a task") { target = activity.id; targetArea = nil; focus = .add }
                    Button("Add a daily area…") { areaDraft = ""; newAreaFor = activity.id }
                } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Add a task, or a daily area: something you do every day for \(activity.name)")
            }
            .padding(.bottom, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(dropArea == activity.id ? Theme.accentTint : .clear))
            .dropDestination(for: String.self) { items, _ in
                model.drop(items, day: today, activity: activity.id, area: nil, before: nil)
            } isTargeted: { dropArea = $0 ? activity.id : (dropArea == activity.id ? nil : dropArea) }
            ForEach(list) { area in
                areaRow(area, activity, items: tasks.filter { $0.area == area.id })
            }
            if newAreaFor == activity.id { newAreaField(activity) }
            ForEach(loose) { task in
                TaskRow(model: model, task: task, day: today, activity: activity, activities: activities, today: today, focus: $focus, selected: $selected)
                Divider().padding(.leading, 30).opacity(0.5)
            }
        }
    }

    // A daily area: a square checkbox for today, its title (edited in place), today's tasks under it.
    private func areaRow(_ area: DailyArea, _ activity: ActivitySetting, items: [ActivityTask]) -> some View {
        let st = ActivityStyle.of(activity)
        let done = model.dailyTasks.isDone(area: area.id, activity: activity.id, day: today)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { model.editTasks { $0.toggle(area: area.id, activity: activity.id, day: today) } } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(done ? Color.clear : st.color, lineWidth: 1.5)
                        if done {
                            RoundedRectangle(cornerRadius: 5).fill(st.color.opacity(0.85))
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Done for today")
                TextField("Daily area", text: Binding(
                    get: { model.dailyTasks.areas(for: activity.id).first { $0.id == area.id }?.title ?? area.title },
                    set: { value in model.editTasks { b in
                        b.setAreas(b.areas(for: activity.id).map { var a = $0; if a.id == area.id { a.title = value }; return a }, for: activity.id)
                    } }))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(done ? Theme.text2 : Theme.text)
                    .strikethrough(done, color: Theme.text2)
                Image(systemName: "repeat").font(.system(size: 10)).foregroundStyle(Theme.text2).help("Every day")
                if !items.isEmpty {
                    Text("\(items.filter(\.completed).count)/\(items.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 8)
                Button { target = activity.id; targetArea = area.id; focus = .add } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.text2).help("Add today's task under \(area.title)")
                Menu {
                    Button("Move up") { moveArea(area.id, activity.id, by: -1) }
                    Button("Move down") { moveArea(area.id, activity.id, by: 1) }
                    Divider()
                    Button("Remove daily area", role: .destructive) { model.editTasks { $0.removeArea(area.id, activity: activity.id) } }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.text2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(dropArea == area.id ? Theme.accentTint : .clear))
            .dropDestination(for: String.self) { items, _ in
                model.drop(items, day: today, activity: activity.id, area: area.id, before: nil)
            } isTargeted: { dropArea = $0 ? area.id : (dropArea == area.id ? nil : dropArea) }
            ForEach(items.filter { !$0.completed }) { task in
                TaskRow(model: model, task: task, day: today, activity: activity, activities: activities, today: today, focus: $focus, selected: $selected)
                    .padding(.leading, 28)
            }
            Divider().padding(.leading, 30).opacity(0.5)
        }
    }

    private func newAreaField(_ activity: ActivitySetting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").font(.system(size: 12)).foregroundStyle(ActivityStyle.of(activity).color).frame(width: 18)
            TextField("Something you do every day, e.g. Solve a problem on bigfrontend.dev", text: $areaDraft)
                .textFieldStyle(.plain).font(.system(size: 13))
                .onSubmit {
                    let title = areaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        let area = DailyArea(title: title)
                        model.editTasks { $0.setAreas($0.areas(for: activity.id) + [area], for: activity.id) }
                        target = activity.id; targetArea = area.id
                    }
                    newAreaFor = nil; areaDraft = ""; focus = .add
                }
            Button("Cancel") { newAreaFor = nil; areaDraft = "" }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
        .padding(.vertical, 7)
    }

    private func moveArea(_ id: UUID, _ activity: UUID, by offset: Int) {
        model.editTasks { b in
            var list = b.areas(for: activity)
            guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + offset) else { return }
            list.swapAt(i, i + offset)
            b.setAreas(list, for: activity)
        }
    }

    private func overdueSection(_ items: [(day: String, activity: UUID, task: ActivityTask)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 12)).foregroundStyle(Theme.red)
                Text("Overdue").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red)
                Text("\(items.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                Spacer()
                Button("Move all to today") {
                    for i in items { model.moveTask(i.task.id, from: i.day, activity: i.activity, to: today, activity: i.activity) }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                Menu {
                    Button("Delete all overdue…", role: .destructive) { asksDeleteOverdue = true }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.text2) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.bottom, 4)
            .confirmationDialog("Delete \(items.count) overdue tasks?", isPresented: $asksDeleteOverdue) {
                Button("Delete", role: .destructive) {
                    for i in items {
                        model.setTasks(model.tasks(for: i.activity, day: i.day).filter { $0.id != i.task.id }, for: i.activity, day: i.day)
                    }
                }
            } message: { Text("Unfinished tasks from earlier days. Completed ones and today's stay.") }
            // A long backlog shouldn't push today off the screen: the oldest five, then the rest on request.
            ForEach(showsAllOverdue ? items : Array(items.prefix(5)), id: \.task.id) { i in
                if let a = activities.first(where: { $0.id == i.activity }) {
                    TaskRow(model: model, task: i.task, day: i.day, activity: a, activities: activities, today: today, focus: $focus, selected: $selected)
                    Divider().padding(.leading, 30).opacity(0.5)
                }
            }
            if items.count > 5 {
                Button(showsAllOverdue ? "Show fewer" : "Show all \(items.count)") { withAnimation(.snappy) { showsAllOverdue.toggle() } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    .padding(.top, 6)
            }
        }
    }

    private func doneSection(_ lists: [(ActivitySetting, [ActivityTask])]) -> some View {
        let done = lists.flatMap { a, tasks in tasks.filter(\.completed).map { (a, $0) } }
        return VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(.snappy) { showsDone.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsDone ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                    Text("Completed").font(.system(size: 13, weight: .semibold))
                    Text("\(done.count)").font(.system(size: 11)).monospacedDigit()
                    Spacer()
                }
                .foregroundStyle(Theme.text2).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
            if showsDone {
                ForEach(done, id: \.1.id) { a, task in
                    TaskRow(model: model, task: task, day: today, activity: a, activities: activities, today: today, focus: $focus, selected: $selected, showsActivity: true)
                }
            }
        }
    }

    private func emptyState(anyDone: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: anyDone ? "checkmark.seal.fill" : "sun.max").font(.system(size: 30))
                .foregroundStyle(anyDone ? Color.green : Theme.accent)
            Text(anyDone ? "All done for today" : "Nothing planned yet").font(.system(size: 14, weight: .semibold))
            Text(anyDone ? "Everything on today's list is checked off." : "Type above and press Return. Pick the activity on the right.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

enum TaskFocus: Hashable { case add, task(UUID) }

// The window's key events, while the Tasks page is open. The handler is replaced on every
// render, so it always sees the current rows, selection and focus.
@MainActor
final class KeyMonitor: ObservableObject {
    var handler: ((NSEvent) -> Bool)?
    private var monitor: Any?
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            nonisolated(unsafe) let event = e   // delivered on the main thread
            let handled = MainActor.assumeIsolated { self?.handler?(event) == true }
            return handled ? nil : e
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// What a dragged task carries: where it's stored, as plain text ("day|activity|task").
struct TaskDrag {
    let day: String, activity: UUID, id: UUID
    var text: String { "\(day)|\(activity.uuidString)|\(id.uuidString)" }
    init(day: String, activity: UUID, id: UUID) { self.day = day; self.activity = activity; self.id = id }
    init?(_ text: String) {
        let p = text.split(separator: "|").map(String.init)
        guard p.count == 3, let a = UUID(uuidString: p[1]), let i = UUID(uuidString: p[2]) else { return nil }
        self.init(day: p[0], activity: a, id: i)
    }
}

extension Model {
    // A task dropped somewhere on the Tasks page: into that day, activity and area, before `before`.
    func drop(_ items: [String], day: String, activity: UUID, area: UUID?, before: UUID?) -> Bool {
        let drags = items.compactMap(TaskDrag.init)
        for d in drags { editTasks { $0.place(d.id, from: d.day, activity: d.activity, to: day, activity: activity, area: area, before: before) } }
        return !drags.isEmpty
    }
}

// A thin accent line where a dragged task would land.
private struct DropLine: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if shown { Capsule().fill(Theme.accent).frame(height: 2).offset(y: -1) }
        }
    }
}

// One task: a round checkbox in the activity's color, the title editable in place, and its
// actions on hover (Todoist-style), so the list stays quiet until you point at something.
private struct TaskRow: View {
    @ObservedObject var model: Model
    let task: ActivityTask
    let day: String
    let activity: ActivitySetting
    let activities: [ActivitySetting]
    let today: String
    var focus: FocusState<TaskFocus?>.Binding
    @Binding var selected: UUID?
    var showsActivity = false
    @State private var hovering = false
    @State private var dropping = false

    private var list: [ActivityTask] { model.tasks(for: activity.id, day: day) }

    var body: some View {
        let st = ActivityStyle.of(activity)
        let overdue = day < today
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { update { $0.completed.toggle() } } label: {
                ZStack {
                    Circle().strokeBorder(task.completed ? Color.clear : st.color, lineWidth: 1.5)
                    if task.completed { Circle().fill(st.color.opacity(0.85)) }
                    if task.completed || hovering {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(task.completed ? .white : st.color)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            .accessibilityLabel(task.completed ? "Mark incomplete: \(task.title)" : "Complete: \(task.title)")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Task", text: Binding(
                    get: { list.first { $0.id == task.id }?.title ?? task.title },
                    set: { value in update { $0.title = value } }),
                    onEditingChanged: { if $0 { selected = task.id } })
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .foregroundStyle(task.completed ? Theme.text2 : Theme.text)
                    .strikethrough(task.completed, color: Theme.text2)
                    .focused(focus, equals: .task(task.id))
                    .onSubmit { focus.wrappedValue = .add }
                if overdue || showsActivity {
                    HStack(spacing: 6) {
                        if overdue {
                            Text(Fmt.dayKey.date(from: day).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? day)
                                .foregroundStyle(Theme.red)
                        }
                        let area = task.area.flatMap { id in model.dailyTasks.areas(for: activity.id).first { $0.id == id } }
                        Label(area.map { "\(activity.name) › \($0.title)" } ?? activity.name, systemImage: st.icon).foregroundStyle(Theme.text2)
                    }
                    .font(.system(size: 11))
                }
            }
            Spacer(minLength: 8)
            if overdue {
                Button("Today") { model.moveTask(task.id, from: day, activity: activity.id, to: today, activity: activity.id) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    .help("Move to today")
            }
            actions.opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected == task.id ? Theme.accentTint.opacity(0.6) : .clear)
            .padding(.horizontal, -6))
        .contentShape(Rectangle())
        .onTapGesture { selected = task.id }
        .onHover { hovering = $0 }
        // Grab it anywhere outside the title (or by the grip on hover) and drop it on another task,
        // an area or an activity: reorder, move between activities, file it under an area.
        .overlay(alignment: .leading) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.text2.opacity(hovering ? 0.8 : 0))
                .offset(x: -18)
        }
        .draggable(TaskDrag(day: day, activity: activity.id, id: task.id).text) {
            Text(task.title).font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        }
        .dropDestination(for: String.self) { items, _ in
            model.drop(items, day: day, activity: activity.id, area: task.area, before: task.id)
        } isTargeted: { dropping = $0 }
        .modifier(DropLine(shown: dropping))
    }

    private var actions: some View {
        Menu {
            if day < today {
                Button("Move to today") { model.moveTask(task.id, from: day, activity: activity.id, to: today, activity: activity.id) }
            }
            Menu("Move to activity") {
                ForEach(activities.filter { $0.id != activity.id }) { other in
                    Button(other.name) { model.moveTask(task.id, from: day, activity: activity.id, to: day, activity: other.id) }
                }
            }
            if task.area == nil {
                Button("Make it a daily area") {
                    let title = task.title, id = task.id, a = activity.id, d = day
                    model.editTasks { b in
                        b.setAreas(b.areas(for: a) + [DailyArea(title: title)], for: a)
                        b.set(b.tasks(day: d, activity: a).filter { $0.id != id }, day: d, activity: a)
                    }
                }
            }
            Button("Move up") { move(by: -1) }.disabled(list.first?.id == task.id)
            Button("Move down") { move(by: 1) }.disabled(list.last?.id == task.id)
            Divider()
            Button("Delete", role: .destructive) { model.setTasks(list.filter { $0.id != task.id }, for: activity.id, day: day) }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.text2)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Task actions: \(task.title)")
    }

    private func update(_ change: (inout ActivityTask) -> Void) {
        var value = list
        guard let i = value.firstIndex(where: { $0.id == task.id }) else { return }
        change(&value[i])
        model.setTasks(value, for: activity.id, day: day)
    }

    private func move(by offset: Int) {
        var value = list
        guard let i = value.firstIndex(where: { $0.id == task.id }), value.indices.contains(i + offset) else { return }
        value.swapAt(i, i + offset)
        model.setTasks(value, for: activity.id, day: day)
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
