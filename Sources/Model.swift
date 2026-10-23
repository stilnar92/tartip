import SwiftUI
import AppKit
import ApplicationServices

final class Model: ObservableObject {
    @Published var blocks: [String] = []
    @Published var selected: String = UserDefaults.standard.string(forKey: "selected") ?? ""
    @Published var minutes: Int = max(1, UserDefaults.standard.integer(forKey: "minutes"))
    @Published var pomodoro: Bool = UserDefaults.standard.bool(forKey: "pomodoro")
    @Published var session: Session?
    @Published var now = Date()
    @Published var message = ""
    @Published var configs: [String: ModeConfig] = [:]
    @Published var desktop: Int = UserDefaults.standard.object(forKey: "desktop") as? Int ?? 7 {
        didSet { UserDefaults.standard.set(desktop, forKey: "desktop") }
    }
    @Published var oneTimeLink = ""
    @Published var restEnd: Date? = UserDefaults.standard.object(forKey: "restEnd") as? Date
    @Published var prompt: Prompt?
    @Published var restTaken = UserDefaults.standard.bool(forKey: "restTaken")
    @Published var stats: DayStats = UserDefaults.standard.data(forKey: "stats")
        .flatMap { try? JSONDecoder().decode(DayStats.self, from: $0) } ?? DayStats(day: dayKey(Date()))
    private var idleSeconds = 0
    private let promptWindow = PromptWindow()
    @Published var activities: [String] = loadActivities()
    @Published var pendingStart: PendingStart?
    @Published var review: SessionRecord? = UserDefaults.standard.data(forKey: "review")
        .flatMap { try? recordCoder().1.decode(SessionRecord.self, from: $0) }
    @Published var records: [SessionRecord] = loadRecords()
    private let activityWindow = PromptWindow()
    private let statsWindow = StatsWindow()

    private var lastPhase: Int?
    private var timer: Timer?

    init() {
        if UserDefaults.standard.integer(forKey: "minutes") < minMinutes { minutes = defaultMinutes }
        loadBlocks()
        if let d = try? Data(contentsOf: configFile), let c = try? JSONDecoder().decode([String: ModeConfig].self, from: d) {
            configs = c
        }
        if let d = UserDefaults.standard.data(forKey: "session"),
           let s = try? JSONDecoder().decode(Session.self, from: d), Date() < s.end {
            session = s
            lastPhase = s.current(at: Date())?.index
        }
        if let s = session {
            // Restarted mid-session: make sure the block is on for the time that's left.
            let left = Int((s.end.timeIntervalSinceNow / 60).rounded(.up))
            if left > 0 { runCT(["-start", s.block, "-lock", String(left)], keep: Double(left * 60 + 60)) }
        } else {
            killStrayCTCommands()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        // Unfinished questions from before a restart.
        DispatchQueue.main.async { [self] in
            if review != nil { activityWindow.show(ReviewView(m: self)) }
            else if session != nil && session?.planned == nil { showPicker() }
        }
    }

    // MARK: blocks list (~/modes/blocks.txt, one name per line)

    func loadBlocks() {
        let text = (try? String(contentsOf: blocksFile, encoding: .utf8)) ?? ""
        blocks = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !blocks.contains(selected) { selected = blocks.first ?? "" }
    }

    func saveBlocks() {
        try? FileManager.default.createDirectory(at: modesDir, withIntermediateDirectories: true)
        try? (blocks.joined(separator: "\n") + "\n").write(to: blocksFile, atomically: true, encoding: .utf8)
    }

    func addBlock(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !blocks.contains(n) else { return }
        blocks.append(n); selected = n; saveBlocks()
    }

    func removeBlock(_ name: String) {
        blocks.removeAll { $0 == name }
        if selected == name { selected = blocks.first ?? "" }
        saveBlocks()
    }

    // MARK: what each mode opens (~/modes/modes.json)

    func config(_ block: String) -> ModeConfig { configs[block] ?? ModeConfig() }

    func updateConfig(_ block: String, _ change: (inout ModeConfig) -> Void) {
        var c = config(block)
        change(&c)
        configs[block] = c
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(configs) { try? d.write(to: configFile) }
        if !(c.apps.isEmpty && c.urls.isEmpty) { _ = axTrusted(prompt: true) }
    }

    func chooseApps(for block: String) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            updateConfig(block) { c in
                for u in panel.urls where !c.apps.contains(u.path) { c.apps.append(u.path) }
            }
        }
    }

    // MARK: session

    var focusBlock: String { blocks.first ?? "Focus_Mode" }

    // Each activity has a Cold Turkey block with the same name; "Other" uses Focus_Mode.
    func blockFor(_ activity: String) -> String { activity == otherActivity ? focusBlock : activity }
    var freeLeft: Int { max(0, dailyFreeSeconds - stats.free) }

    private func chosenPhases() -> [Phase] {
        guard pomodoro else { return [Phase(isBreak: false, minutes: minutes)] }
        var phases: [Phase] = []
        for i in 0..<4 {
            phases.append(Phase(isBreak: false, minutes: 25))
            if i < 3 { phases.append(Phase(isBreak: true, minutes: 5)) }
        }
        return phases
    }

    // Start button in the panel.
    func start() {
        if minutes < minMinutes { minutes = minMinutes }
        let d = UserDefaults.standard
        d.set(selected, forKey: "selected"); d.set(minutes, forKey: "minutes")
        d.set(pomodoro, forKey: "pomodoro")
        let extra = oneTimeLink.trimmingCharacters(in: .whitespaces)
        oneTimeLink = ""
        // Nothing starts until the activity is picked.
        pendingStart = PendingStart(block: selected, phases: chosenPhases(), extra: extra.isEmpty ? [] : [extra])
        showPicker()
    }

    // Prompt: start a mode with the duration last chosen in the panel.
    func startFromPrompt(_ block: String) {
        dismissPrompt()
        pendingStart = PendingStart(block: block, phases: chosenPhases(), extra: [])
        showPicker()
    }

    // MARK: activity: pick before, review after

    var pendingLabel: String {
        guard let p = pendingStart else { return "" }
        let total = p.phases.reduce(0) { $0 + $1.minutes }
        return p.phases.count > 1 ? "Pomodoro · \(formatDuration(total * 60))" : "\(total) min"
    }

    func showPicker() {
        activities = loadActivities()   // pick up edits to activities.txt
        activityWindow.show(ActivityPickerView(m: self))
    }

    func choosePlan(_ activity: String, note: String?, minutes chosen: Int) {
        activityWindow.hide()
        let mins = max(minMinutes, chosen)
        if let p = pendingStart {
            pendingStart = nil
            // Pomodoro keeps its rounds; otherwise the duration picked here wins.
            let phases = p.phases.count > 1 ? p.phases : [Phase(isBreak: false, minutes: mins)]
            start(block: blockFor(activity), phases: phases, extra: p.extra, planned: activity, note: note)
        } else if var s = session {
            // Auto-started session: record the plan and set its length from the pick.
            s.planned = activity; s.note = note; s.pickedAt = Date()
            if s.workRounds == 1 {
                let total = Int(Date().timeIntervalSince(s.start) / 60) + mins
                s.phases = [Phase(isBreak: false, minutes: total)]
                // Cold Turkey can only lengthen a lock, so re-send the start for the new end.
                let left = Int((s.end.timeIntervalSinceNow / 60).rounded(.up))
                runCT(["-start", s.block, "-lock", String(left)], keep: Double(left * 60 + 60))
            }
            session = s
            if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "session") }
            log("plan  \(activity)\(note.map { " (\($0))" } ?? "")")
        }
    }

    func cancelPick() {
        pendingStart = nil
        activityWindow.hide()
    }

    private func beginReview(_ s: Session) {
        let r = SessionRecord(start: s.pickedAt ?? s.start, end: min(Date(), s.end), mode: s.block, planned: s.planned, note: s.note)
        guard r.seconds >= 60 else { return }   // ignore sessions under a minute
        review = r
        if let d = try? recordCoder().0.encode(r) { UserDefaults.standard.set(d, forKey: "review") }
        activityWindow.show(ReviewView(m: self))
    }

    func saveReview(actual: [String], note: String?) {
        guard var r = review else { return }
        r.actual = actual
        if let note { r.note = note }
        appendRecord(r)
        records.append(r)
        review = nil
        UserDefaults.standard.removeObject(forKey: "review")
        activityWindow.hide()
        log("did   \(actual.joined(separator: ", "))\(r.asPlanned ? " (as planned)" : "")")
    }

    func reloadRecords() { records = loadRecords(); activities = loadActivities() }

    func openStats() { statsWindow.show(StatsView(m: self)) }

    func start(block: String, phases: [Phase], extra: [String] = [], autoThinking: Bool = false,
               planned: String? = nil, note: String? = nil) {
        dismissPrompt()
        restTaken = false
        UserDefaults.standard.set(false, forKey: "restTaken")
        restEnd = nil
        UserDefaults.standard.removeObject(forKey: "restEnd")
        idleSeconds = 0

        let s = Session(block: block, phases: phases, start: Date(), autoThinking: autoThinking, planned: planned, note: note)
        runCT(["-start", s.block, "-lock", String(s.totalMinutes)], keep: Double(s.totalMinutes * 60 + 60))
        message = ""
        let c = config(s.block)
        let hasStuff = !(c.apps.isEmpty && c.urls.isEmpty && extra.isEmpty)
        if (hasStuff || desktop > 0) && !axTrusted(prompt: true) {
            message = "Allow Focus Modes in Privacy & Security → Accessibility to switch desktops and resize windows."
        }
        let prev = UserDefaults.standard.data(forKey: "opened").flatMap { try? JSONDecoder().decode(OpenedWorkspace.self, from: $0) }
        openWorkspace(mode: s.block, c, extraURLs: extra, desktop: desktop, prev: prev) { opened in
            if let data = try? JSONEncoder().encode(opened) { UserDefaults.standard.set(data, forKey: "opened") }
        }

        session = s
        lastPhase = 0
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "session") }
        let desc = s.workRounds > 1 ? "pomodoro 25/5x4" : "\(s.totalMinutes)m"
        log("start \(s.block) (app\(autoThinking ? ", auto" : ""), \(desc), lock \(s.totalMinutes)m)")
        notify("Focus: \(s.block)", s.workRounds > 1 ? "Round 1/4 — 25 min. Go!" : "\(s.totalMinutes) min. Go!")
    }

    func stop() {
        guard let s = session else { return }
        if Date() < s.end {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            message = "Locked until \(f.string(from: s.end)). Timer stopped, block stays."
        }
        runCT(["-stop", s.block])
        log("off   \(s.block) (app)")
        endSession()
        beginReview(s)
    }

    private func endSession() {
        session = nil
        lastPhase = nil
        idleSeconds = 0
        UserDefaults.standard.removeObject(forKey: "session")
    }

    // MARK: rest (free time, counted against the daily budget)

    // Rest can't be chosen twice in a row: a mode has to run in between.
    var canRest: Bool { freeLeft >= 60 && !restTaken }

    func startRest(minutes: Int) {
        guard session == nil, canRest else { return }
        restTaken = true
        UserDefaults.standard.set(true, forKey: "restTaken")
        dismissPrompt()
        let secs = min(min(minutes, 15) * 60, freeLeft)   // one stretch is at most 15 min
        restEnd = Date().addingTimeInterval(Double(secs))
        UserDefaults.standard.set(restEnd, forKey: "restEnd")
        log("rest  \(secs / 60)m (\(freeLeft / 60)m left today)")
    }

    func endRest() {
        restEnd = nil
        idleSeconds = 0
        UserDefaults.standard.removeObject(forKey: "restEnd")
    }

    // MARK: prompt

    private func showPrompt(_ kind: PromptKind) {
        guard prompt == nil else { return }
        prompt = Prompt(kind: kind, deadline: Date().addingTimeInterval(promptCountdown))
        NSSound(named: "Funk")?.play()
        promptWindow.show(PromptView(m: self))
        log("prompt \(kind)")
    }

    func dismissPrompt() {
        prompt = nil
        promptWindow.hide()
    }

    // What the prompt does when the countdown ends (or "Start now").
    func promptDefault() {
        guard let p = prompt else { return }
        _ = p
        // Nothing is blocked until an activity is picked; then its own block starts.
        dismissPrompt()
        pendingStart = PendingStart(block: focusBlock, phases: [Phase(isBreak: false, minutes: defaultMinutes)], extra: [], auto: true)
        showPicker()
    }

    var promptDefaultLabel: String {
        guard let p = prompt else { return "" }
        _ = p
        return "pick what to work on"
    }

    // MARK: tick

    private func saveStats() {
        if let d = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(d, forKey: "stats") }
    }

    private func tick() {
        now = Date()
        if stats.day != dayKey(now) { stats = DayStats(day: dayKey(now)) }
        let enforce = enforcementActive(now)
        defer { if Int(now.timeIntervalSince1970) % 10 == 0 { saveStats() } }

        if let p = prompt, now >= p.deadline { promptDefault() }

        if let s = session {
            guard let cur = s.current(at: now) else {
                log("done  \(s.block) (app)")
                runCT(["-stop", s.block])
                endSession()
                // After auto Thinking nothing else is forced; the 15-min idle clock starts again.
                notify("Focus: \(s.block)", "Session done 🎉")
                beginReview(s)
                return
            }
            stats.focus += 1
            if cur.index != lastPhase {
                lastPhase = cur.index
                let p = s.phases[cur.index]
                if p.isBreak { notify("Break \(p.minutes) min", "Stand up, drink water. Next round starts automatically.") }
                else { notify("Round \(s.round(of: cur.index))/\(s.workRounds)", "\(p.minutes) min. Back to work!") }
            }
            return
        }

        if let r = restEnd {
            if now < r {
                stats.free += 1
                return
            }
            endRest()
            if enforce { showPrompt(.restOver) } else { notify("Rest is over", "Pick a mode when you're ready.") }
            return
        }

        // Idle: no mode, no rest.
        // Answering a question isn't idle time.
        guard enforce, prompt == nil, review == nil, pendingStart == nil, userPresent() else { return }
        stats.free += 1
        idleSeconds += 1
        if freeLeft <= 0 { showPrompt(.budget) }
        else if idleSeconds >= idleNudgeSeconds { showPrompt(.idle) }
    }

    // MARK: display

    func remaining(_ until: Date) -> String {
        let sec = max(0, Int(until.timeIntervalSince(now)))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    var menuTitle: String {
        if let r = restEnd { return "☕ " + remaining(r) }
        guard let s = session, let cur = s.current(at: now) else { return "🎯" }
        return (s.phases[cur.index].isBreak ? "☕ " : "🎯 ") + remaining(cur.end)
    }
}

func formatDuration(_ secs: Int) -> String {
    let m = secs / 60
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
