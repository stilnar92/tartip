import SwiftUI

// Today on one time axis. Available: what you can still pick, by period (any-time ones listed
// once above; red where nothing at all can start). Actual: the sessions that ran, marked by
// their own real times, not Available's. Compare shows both side by side.
struct DayTimeline: View {
    let day: Model.DayView
    var editable = false       // Edit hours: drag each activity's hours, for this weekday only

    private enum Mode: String, CaseIterable, Identifiable { case available, actual, compare; var id: Self { self } }
    @State private var mode: Mode = .available
    // Edit hours works on a draft of the activities: Undo/Redo step through it, Apply saves it.
    @State private var draft: [ActivitySetting]?
    @State private var undoStack: [[ActivitySetting]] = []
    @State private var redoStack: [[ActivitySetting]] = []
    @State private var drag: Drag?
    @State private var picked: String?     // the block whose time fields are open
    private var editing: Bool { draft != nil }
    @ObservedObject private var settings = Settings.shared
    // Another day has only its plan; editing works on the plan.
    private var shown: Mode { day.planOnly || editing ? .available : mode }

    private let hourHeight: CGFloat = 56   // a 15-minute session still gets its label
    private let labelWidth: CGFloat = 40

    private func y(_ m: Int) -> CGFloat { CGFloat(m - day.from) / 60 * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !day.overcommitted.isEmpty {
                Label(
                    "Won't fit in \(day.planOnly ? "this day's" : "today's") hours: " + day.overcommitted.joined(separator: ", "),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .help("These activities' daily limits can't all fit in the hours they share today, even spread across their own other windows.")
            }
            if !day.anyTime.isEmpty {
                (Text("Any time  ").foregroundColor(Theme.text2) + names(day.anyTime))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if shown == .compare {
                    Color.clear.frame(width: labelWidth, height: 1)
                    title("Available", day.anyTime.isEmpty ? "what you can pick" : "plus the any-time ones")
                    title("Actual", "by their real time")
                } else {
                    title(shown == .actual ? "Actual" : "Available",
                          shown == .actual ? "the sessions you ran, by their real time"
                          : (day.anyTime.isEmpty ? "what you can pick, by period" : "plus the any-time ones"))
                }
                Spacer()
                if editable && !editing {
                    Button {
                        draft = settings.value.activities
                        undoStack = []; redoStack = []; drag = nil
                    } label: {
                        Label("Edit hours", systemImage: "hand.draw")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .pill(selected: false)
                    }
                    .buttonStyle(.plain)
                    .help("Drag each activity's hours on \(weekdayShort[day.weekday] ?? "this day") only")
                }
                if !day.planOnly && !editing {
                    Picker("", selection: $mode) {
                        Text("Available").tag(Mode.available)
                        Text("Actual").tag(Mode.actual)
                        Text("Compare").tag(Mode.compare)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
            if editing { editBar }
            HStack(alignment: .top, spacing: 8) {
                hourLabels(editing ? blockMarks : shown == .actual ? actualMarks : availableMarks)
                if editing {
                    editColumn
                } else if shown == .available {
                    availableColumn
                } else if shown == .actual {
                    actualColumn
                } else {
                    availableColumn
                    actualColumn
                }
            }
        }
    }

    private var availableColumn: some View {
        column(availableMarks) { w in
            ForEach(Array(day.periods.enumerated()), id: \.offset) { i, p in
                period(p, shade: i % 2 == 0).frame(width: w, height: max(2, y(p.end) - y(p.start) - 3)).offset(y: y(p.start) + 1.5)
            }
        }
    }

    private var actualColumn: some View {
        column(shown == .compare ? availableMarks : actualMarks) { w in
            ForEach(Array(day.actual.enumerated()), id: \.offset) { _, s in
                session(s).frame(width: w, height: max(2, y(s.end) - y(s.start) - 2)).offset(y: y(s.start) + 1)
            }
        }
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            Text(sub).font(.system(size: 10)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Available's marks: where periods start and end, that's when what you can pick changes.
    private var availableMarks: [Int] { Array(Set(day.periods.flatMap { [$0.start, $0.end] } + [day.from, day.to])).sorted() }
    // Actual's marks: the real start and end of every session that ran, not Available's periods.
    private var actualMarks: [Int] { Array(Set(day.actual.flatMap { [$0.start, $0.end] } + [day.from, day.to])).sorted() }

    // Marks whose labels would overlap (too close in time to fit two lines of text) drop all
    // but the first; the grid lines themselves still show at every real mark.
    private func spacedOut(_ marks: [Int]) -> [Int] {
        var out: [Int] = []
        for m in marks {
            if let last = out.last, y(m) - y(last) < 14 { continue }
            out.append(m)
        }
        return out
    }

    private func hourLabels(_ marks: [Int]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(spacedOut(marks), id: \.self) { m in
                Text(clockLabel(m % 1440)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .offset(y: y(m) - 6)
            }
        }
        .frame(width: labelWidth, height: y(day.to), alignment: .topLeading)
    }

    private func column<Content: View>(_ marks: [Int], @ViewBuilder _ content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { m in
                    Rectangle().fill(Theme.separator).frame(width: g.size.width, height: 1).offset(y: y(m))
                }
                content(g.size.width)
                if let now = day.now {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.red).frame(width: 7, height: 7)
                        Rectangle().fill(Theme.red).frame(height: 1.5)
                    }
                    .frame(width: g.size.width).offset(y: y(now) - 3.5)
                }
            }
        }
        .frame(height: y(day.to))
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: available

    // Names in their own colors, separated by dots; wraps like text.
    private func names(_ list: [String]) -> Text {
        var t = Text("")
        for (i, name) in list.enumerated() {
            if i > 0 { t = t + Text("  ·  ").foregroundColor(Theme.text2) }
            t = t + Text(name).foregroundColor(ActivityStyle.of(name).color)
        }
        return t
    }

    // Nothing at all can start: no activity with hours open, and none for any time either.
    private func isEmpty(_ p: Period) -> Bool { p.available.isEmpty && day.anyTime.isEmpty }

    private func period(_ p: Period, shade: Bool) -> some View {
        let h = y(p.end) - y(p.start)
        let empty = isEmpty(p)
        let isNow = day.now.map { $0 >= p.start && $0 < p.end } ?? false
        let past = day.now.map { p.end <= $0 } ?? false
        let fill: Color = empty ? Theme.redTint.opacity(0.7) : isNow ? Theme.accentTint : Theme.accent.opacity(shade ? 0.05 : 0.10)
        let edge: Color = empty ? Theme.red.opacity(0.5) : isNow ? Theme.accent.opacity(0.5) : .clear
        let locked = day.lockedGaps.contains(Gap(from: p.start, to: p.end))
        let label: Text = empty ? Text(locked ? "Nothing can start · step away" : "Nothing can start · free").foregroundColor(Theme.red)
            : p.available.isEmpty ? Text("Only any-time  ").foregroundColor(Theme.text2) + names(day.anyTime)
            : names(p.available)
        let what = empty ? "nothing can start" : (p.available + day.anyTime).joined(separator: ", ")
        return label
            .font(.system(size: 11, weight: .semibold))
            .lineSpacing(2)
            .padding(.horizontal, 8).padding(.vertical, h >= 24 ? 5 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: h >= 24 ? .topLeading : .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(edge, style: StrokeStyle(lineWidth: 1, dash: empty ? [4, 3] : [])))
            .opacity(past ? 0.5 : 1)
            .clipped()
            .help("\(clockLabel(p.start % 1440))–\(clockLabel(p.end % 1440)): " + what)
    }

    // MARK: edit hours

    // One window of one activity on this weekday, in the day's minutes (which may pass 1440).
    // Overlapping blocks share the width side by side: `lane` of `lanes`.
    private struct Block: Identifiable {
        var id: String { "\(activity)-\(index)" }
        let activity: UUID
        let name: String
        let index: Int
        let start: Int
        let end: Int
        let ownDay: Bool        // the weekday has its own hours, not the usual ones
        var lane = 0
        var lanes = 1
    }

    private enum Grip { case move, top, bottom }
    private struct Drag { let id: String; let grip: Grip; var delta: Int }

    private var blocks: [Block] {
        let d = day.weekday
        var out: [Block] = []
        for a in draft ?? settings.value.activities where !a.name.isEmpty && a.isPlanned(onWeekday: d) {
            let list = a.windows(onWeekday: d)
            for (i, w) in list.enumerated() where w.from != w.to {
                var start = w.from
                if start < day.from && start + 1440 < day.to { start += 1440 }   // the waking day runs past midnight
                out.append(Block(activity: a.id, name: a.name, index: i, start: start, end: start + (w.to - w.from + 1440) % 1440, ownDay: a.dayWindows[d] != nil))
            }
        }
        out.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        // Lanes per cluster of overlapping blocks, so a lone block keeps the full width.
        var k = 0
        while k < out.count {
            var clusterEnd = out[k].end, laneEnds: [Int] = [], j = k
            while j < out.count && (j == k || out[j].start < clusterEnd) {
                if let l = laneEnds.firstIndex(where: { $0 <= out[j].start }) { out[j].lane = l; laneEnds[l] = out[j].end }
                else { out[j].lane = laneEnds.count; laneEnds.append(out[j].end) }
                clusterEnd = max(clusterEnd, out[j].end)
                j += 1
            }
            for m in k..<j { out[m].lanes = laneEnds.count }
            k = j
        }
        return out
    }

    // Where a block is drawn: its own place, or where the drag would put it (15-minute steps).
    private func span(_ b: Block) -> (start: Int, end: Int) {
        guard let g = drag, g.id == b.id else { return (b.start, b.end) }
        switch g.grip {
        case .move:
            let delta = min(max(g.delta, day.from - b.start), day.to - b.end)
            return (b.start + delta, b.end + delta)
        case .top: return (min(max(b.start + g.delta, day.from), b.end - 15), b.end)
        case .bottom: return (b.start, max(min(b.end + g.delta, day.to), b.start + 15))
        }
    }

    // The draft's marks: where its blocks start and end.
    private var blockMarks: [Int] { Array(Set(blocks.flatMap { [$0.start, $0.end] } + [day.from, day.to])).sorted() }

    // Undo, Redo, Cancel, Apply. Nothing is saved before Apply; Cancel drops the draft.
    private var editBar: some View {
        let changes = undoStack.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                editButton("Undo", "arrow.uturn.backward", enabled: !undoStack.isEmpty) {
                    redoStack.append(draft ?? []); draft = undoStack.popLast()
                }
                .keyboardShortcut("z", modifiers: .command)
                editButton("Redo", "arrow.uturn.forward", enabled: !redoStack.isEmpty) {
                    undoStack.append(draft ?? []); draft = redoStack.popLast()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                Text(changes == 0 ? "No changes yet" : changes == 1 ? "1 change, not saved" : "\(changes) changes, not saved")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
                Spacer()
                editButton("Cancel", nil, enabled: true) { draft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(action: apply) {
                    Text("Apply").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(changes == 0 ? Theme.text2.opacity(0.4) : Theme.accent))
                }
                .buttonStyle(.plain).disabled(changes == 0)
            }
            Text("Drag a block to move it, its top or bottom edge to resize, right-click to delete it. Each change is for that weekday only; you can switch days before applying.")
                .font(.system(size: 11)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editButton(_ title: String, _ icon: String?, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .pill(selected: false)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    // Saves the draft's days and hours into the activities as they are now, so anything else
    // changed meanwhile stays. Refused by the settings lock: the draft stays to keep or cancel.
    private func apply() {
        guard let draft else { return }
        var s = settings.value
        for d in draft {
            guard let i = s.activities.firstIndex(where: { $0.id == d.id }) else { continue }
            s.activities[i].days = d.days
            s.activities[i].dayMinutes = d.dayMinutes
            s.activities[i].dayWindows = d.dayWindows
        }
        settings.value = s
        if settings.value == s { self.draft = nil }
    }

    private var editColumn: some View {
        column(blockMarks) { w in
            ForEach(blocks) { b in
                let laneWidth = w / CGFloat(b.lanes)
                editBlock(b).frame(width: laneWidth - 2, height: max(8, y(span(b).end) - y(span(b).start) - 2))
                    .offset(x: CGFloat(b.lane) * laneWidth, y: y(span(b).start) + 1)
            }
        }
    }

    private func dragGesture(_ b: Block, _ grip: Grip) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let minutes = Int((v.translation.height / hourHeight * 60 / 15).rounded()) * 15
                drag = Drag(id: b.id, grip: grip, delta: minutes)
            }
            .onEnded { _ in
                let to = span(b)
                drag = nil
                guard to != (b.start, b.end) else { return }
                change(b) { $0.moveWindow(b.index, onWeekday: day.weekday, from: to.start, to: to.end) }
            }
    }

    // Edits that activity in the draft, one Undo step; a refused change (an overlap) leaves it.
    private func change(_ b: Block, _ edit: (inout ActivitySetting) -> Bool) {
        guard var list = draft, let i = list.firstIndex(where: { $0.id == b.activity }), edit(&list[i]) else { return }
        undoStack.append(draft ?? [])
        redoStack = []
        draft = list
    }

    private func editBlock(_ b: Block) -> some View {
        let color = ActivityStyle.of(b.name).color
        let (start, end) = span(b)
        let h = y(end) - y(start)
        let dayName = weekdayShort[day.weekday] ?? "this day"
        let edge = { (grip: Grip) in
            Color.clear.frame(height: 7).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                .gesture(dragGesture(b, grip))
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(b.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).lineLimit(1)
            if h >= 30 {
                Text("\(clockLabel(start % 1440))–\(clockLabel(end % 1440))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.text2)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, h >= 24 ? 4 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: h >= 24 ? .topLeading : .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(drag?.id == b.id ? 0.30 : 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(color.opacity(0.55), lineWidth: 1))
        .clipped()
        .contentShape(Rectangle())
        .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
        .gesture(dragGesture(b, .move))
        .onTapGesture { picked = b.id }
        .popover(isPresented: Binding(get: { picked == b.id }, set: { if !$0 { picked = nil } }), arrowEdge: .trailing) {
            BlockTimeEditor(name: b.name, dayName: dayName, from: b.start % 1440, to: b.end % 1440,
                save: { from, to in
                    var ok = false
                    change(b) { ok = $0.moveWindow(b.index, onWeekday: day.weekday, from: from, to: to); return ok }
                    if ok { picked = nil }
                    return ok
                },
                delete: {
                    change(b) { $0.deleteWindow(b.index, onWeekday: day.weekday) }
                    picked = nil
                })
        }
        .overlay(alignment: .top) { edge(.top) }
        .overlay(alignment: .bottom) { edge(.bottom) }
        .contextMenu {
            Button("Delete this block (\(dayName) only)") { change(b) { $0.deleteWindow(b.index, onWeekday: day.weekday) } }
            if b.ownDay {
                Button("Back to usual hours on \(dayName)") {
                    change(b) { a in a.dayWindows[day.weekday] = nil; return true }
                }
            }
        }
        .help("\(b.name) \(clockLabel(start % 1440))–\(clockLabel(end % 1440)) on \(dayName)")
    }

    // MARK: actual

    @ViewBuilder private func session(_ s: PlanSlot) -> some View {
        let h = y(s.end) - y(s.start)
        let tall = h >= 24
        let fits = h >= 12
        if s.away {
            Label("Away · \(minutesLabel(s.minutes))", systemImage: "figure.walk")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tall ? .topLeading : .leading)
                .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
                .opacity(fits ? 1 : 0)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accentTint))
                .help("Away from the computer \(clockLabel(s.start % 1440))–\(clockLabel(s.end % 1440))")
        } else if s.free {
            Text("🍿 Free time · \(minutesLabel(s.minutes))")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tall ? .topLeading : .leading)
                .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
                .opacity(fits ? 1 : 0)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.yellow.opacity(0.3)))
                .help("Free time \(clockLabel(s.start % 1440))–\(clockLabel(s.end % 1440))")
        } else if let name = s.activity {
            let st = ActivityStyle.of(name)
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(minutesLabel(s.minutes)).font(.system(size: 10)).opacity(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
            .frame(maxHeight: .infinity, alignment: tall ? .top : .center)
            .opacity(fits ? 1 : 0)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(st.color.opacity(0.85)))
            .help("\(name) \(clockLabel(s.start % 1440))–\(clockLabel(s.end % 1440))")
        } else {
            Text("No session · \(minutesLabel(s.minutes))")
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tall ? .topLeading : .leading)
                .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
                .opacity(fits ? 1 : 0)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.pill.opacity(0.6)))
        }
    }
}

// Today in one bar, for the panel: what ran until now, then the periods ahead (red where
// nothing can start).
struct DayStrip: View {
    let day: Model.DayView

    var body: some View {
        let span = CGFloat(max(1, day.to - day.from))
        let now = day.now ?? day.from
        let ahead = day.periods.compactMap { p -> Period? in
            guard p.end > now else { return nil }
            var q = p
            q.start = max(p.start, now)
            return q
        }
        let isEmpty = { (p: Period) in p.available.isEmpty && day.anyTime.isEmpty }
        let empty = ahead.filter(isEmpty).map(\.minutes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { g in
                let x = { (m: Int) in g.size.width * CGFloat(m - day.from) / span }
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Theme.pill).frame(width: g.size.width, height: 12)
                    ForEach(Array(day.actual.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(s.away ? Theme.accent.opacity(0.35) : s.free ? Color.yellow.opacity(0.5) : s.activity.map { ActivityStyle.of($0).color.opacity(0.9) } ?? Theme.text2.opacity(0.2))
                            .frame(width: max(1.5, x(s.end) - x(s.start) - 1), height: 12).offset(x: x(s.start))
                            .help(s.away ? "Away" : s.free ? "Free time" : s.activity.map { "\($0) \(clockLabel(s.start % 1440))–\(clockLabel(s.end % 1440))" } ?? "No session")
                    }
                    ForEach(Array(ahead.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isEmpty(p) ? Theme.red.opacity(0.55) : Theme.accent.opacity(0.15))
                            .frame(width: max(1.5, x(p.end) - x(p.start) - 1), height: 12).offset(x: x(p.start))
                            .help("\(clockLabel(p.start % 1440))–\(clockLabel(p.end % 1440)): "
                                  + (isEmpty(p) ? "nothing can start" : (p.available + day.anyTime).joined(separator: ", ")))
                    }
                    if let n = day.now {
                        Rectangle().fill(Theme.text).frame(width: 2, height: 18).offset(x: x(n) - 1, y: -3)
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 8) {
                Text(clockLabel(day.from % 1440))
                if empty > 0 {
                    Label(minutesLabel(empty) + " with nothing to start", systemImage: "exclamationmark.circle").foregroundStyle(Theme.red)
                }
                Spacer()
                Text(clockLabel(day.to % 1440))
            }
            .font(.system(size: 10)).foregroundStyle(Theme.text2)
        }
    }
}

// A block's hours as two time fields (type or use the arrows), saved into the draft.
private struct BlockTimeEditor: View {
    let name: String
    let dayName: String
    let save: (Int, Int) -> Bool
    let delete: () -> Void
    @State private var from: Date
    @State private var to: Date
    @State private var refused = false

    init(name: String, dayName: String, from: Int, to: Int, save: @escaping (Int, Int) -> Bool, delete: @escaping () -> Void) {
        self.name = name; self.dayName = dayName; self.save = save; self.delete = delete
        _from = State(initialValue: Self.date(from))
        _to = State(initialValue: Self.date(to))
    }

    private static func date(_ m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(_ d: Date) -> Int { minuteOfDay(d) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ActivityStyle.of(name).color)
            HStack(spacing: 8) {
                DatePicker("From", selection: $from, displayedComponents: .hourAndMinute).labelsHidden()
                Text("–").foregroundStyle(Theme.text2)
                DatePicker("To", selection: $to, displayedComponents: .hourAndMinute).labelsHidden()
            }
            .datePickerStyle(.field)
            .environment(\.locale, Locale(identifier: "en_GB"))   // 24-hour, like the rest of the app
            .onChange(of: from) { _ in refused = false }
            .onChange(of: to) { _ in refused = false }
            if refused {
                Text("Overlaps its other hours that day, or is empty.")
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
            }
            Text("For \(dayName) only. Saved when you click Apply.")
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
            HStack {
                Button("Delete block", role: .destructive, action: delete)
                Spacer()
                Button("Set") { refused = !save(Self.minutes(from), Self.minutes(to)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 250)
    }
}
