import SwiftUI
import AppKit
import ApplicationServices
import Combine

final class Model: ObservableObject {
    @Published var blocks: [String] = []
    @Published var selected: String = UserDefaults.standard.string(forKey: "selected") ?? ""
    @Published var minutes: Int = max(1, UserDefaults.standard.integer(forKey: "minutes"))
    @Published var pomodoro: Bool = UserDefaults.standard.bool(forKey: "pomodoro")
    @Published var session: Session?
    @Published var now = Date()
    @Published var message = ""
    @Published var configs: [String: ModeConfig] = [:]
    @Published var oneTimeLink = ""
    @Published var restEnd: Date? = UserDefaults.standard.object(forKey: "restEnd") as? Date
    @Published var restTaken = UserDefaults.standard.bool(forKey: "restTaken")
    @Published var stats: DayStats = UserDefaults.standard.data(forKey: "stats")
        .flatMap { try? JSONDecoder().decode(DayStats.self, from: $0) } ?? DayStats(day: dayKey(Date()))
    @Published var activities: [String] = loadActivities()
    @Published var pendingStart: PendingStart?
    @Published var review: SessionRecord? = UserDefaults.standard.data(forKey: "review")
        .flatMap { try? recordCoder().1.decode(SessionRecord.self, from: $0) }
    @Published var records: [SessionRecord] = loadRecords()
    private let activityWindow = PromptWindow()
    private let statsWindow = StatsWindow()
    private let settingsWindow = StatsWindow(title: "Focus settings")

    private var lastPhase: Int?
    private var timer: Timer?

    private var settingsSub: AnyCancellable?

    init() {
        // Settings edits refresh the panel and the activity list right away.
        settingsSub = Settings.shared.$v.dropFirst().sink { [weak self] v in
            self?.objectWillChange.send()
            self?.activities = v.activities.map(\.name).filter { !$0.isEmpty }
        }
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

    var focusBlock: String { S.otherBlock }

    // Each activity has a Cold Turkey block with the same name; "Other" uses Focus_Mode.
    func blockFor(_ activity: String) -> String { activity == otherActivity ? focusBlock : activity }
    var freeLeft: Int { max(0, dailyFreeSeconds - stats.free) }

    private func chosenPhases() -> [Phase] {
        guard pomodoro else { return [Phase(isBreak: false, minutes: minutes)] }
        var phases: [Phase] = []
        let rounds = max(1, S.pomodoroRounds)
        for i in 0..<rounds {
            phases.append(Phase(isBreak: false, minutes: S.pomodoroWork))
            if i < rounds - 1 { phases.append(Phase(isBreak: true, minutes: S.pomodoroBreak)) }
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

    // MARK: activity: pick before, review after

    var pendingLabel: String {
        guard let p = pendingStart else { return "" }
        let total = p.phases.reduce(0) { $0 + $1.minutes }
        return p.phases.count > 1 ? "Pomodoro · \(formatDuration(total * 60))" : "\(total) min"
    }

    func showPicker() {
        activities = loadActivities()
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

    // MARK: daily limits

    // Sessions since `from`, plus the running one (under its planned activity).
    func recordsSince(_ from: Date) -> [SessionRecord] {
        var recs = records.filter { $0.start >= from }
        if let s = session, let planned = s.planned {
            recs.append(SessionRecord(start: s.pickedAt ?? s.start, end: min(now, s.end), mode: s.block, planned: planned))
        }
        return recs
    }

    // Seconds per activity: what was actually done, or what was planned until it's reviewed,
    // split evenly when a session covered several activities.
    func secondsByActivity(since from: Date) -> [String: Int] {
        var out: [String: Int] = [:]
        for r in recordsSince(from) {
            let acts = r.actual.isEmpty ? [r.planned ?? otherActivity] : r.actual
            for a in acts { out[a, default: 0] += r.seconds / acts.count }
        }
        return out
    }

    // Daily limit in minutes (0 = none).
    func limitMinutes(_ activity: String) -> Int {
        S.activities.first { $0.name == activity }?.dailyMinutes ?? 0
    }

    // Seconds left today, or nil when the activity has no limit.
    func secondsLeftToday(_ activity: String) -> Int? {
        let limit = limitMinutes(activity)
        guard limit > 0 else { return nil }
        let used = secondsByActivity(since: Calendar.current.startOfDay(for: now))[activity] ?? 0
        return max(0, limit * 60 - used)
    }

    // What the picker offers: activities without a limit, or with time left today.
    var availableActivities: [String] {
        activities.filter { (secondsLeftToday($0) ?? 1) > 0 }
    }

    func openStats() { statsWindow.show(StatsView(m: self)) }

    func openSettings() { settingsWindow.show(SettingsView()) }

    func start(block: String, phases: [Phase], extra: [String] = [], autoThinking: Bool = false,
               planned: String? = nil, note: String? = nil) {
        restTaken = false
        UserDefaults.standard.set(false, forKey: "restTaken")
        restEnd = nil
        UserDefaults.standard.removeObject(forKey: "restEnd")

        let s = Session(block: block, phases: phases, start: Date(), autoThinking: autoThinking, planned: planned, note: note)
        runCT(["-start", s.block, "-lock", String(s.totalMinutes)], keep: Double(s.totalMinutes * 60 + 60))
        message = ""
        let c = config(s.block)
        let hasStuff = !(c.apps.isEmpty && c.urls.isEmpty && extra.isEmpty)
        if hasStuff && c.maximize && !axTrusted(prompt: true) {
            message = "Allow Focus Modes in Privacy & Security → Accessibility to resize windows."
        }
        let prev = UserDefaults.standard.data(forKey: "opened").flatMap { try? JSONDecoder().decode(OpenedWorkspace.self, from: $0) }
        openWorkspace(mode: s.block, c, extraURLs: extra, prev: prev) { opened in
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
        UserDefaults.standard.removeObject(forKey: "session")
    }

    // MARK: free time (nothing blocked, from the daily budget, only taken on purpose)

    // Free time can't be taken twice in a row: a session has to run in between.
    var canRest: Bool { freeLeft >= 60 && !restTaken }

    func startRest(minutes: Int) {
        guard session == nil, canRest else { return }
        restTaken = true
        UserDefaults.standard.set(true, forKey: "restTaken")
        if pendingStart != nil { cancelPick() }
        let secs = min(min(minutes, S.maxRestMinutes) * 60, freeLeft)   // one stretch is capped (Settings)
        restEnd = Date().addingTimeInterval(Double(secs))
        UserDefaults.standard.set(restEnd, forKey: "restEnd")
        log("rest  \(secs / 60)m (\(freeLeft / 60)m left today)")
    }

    func endRest() {
        restEnd = nil
        UserDefaults.standard.removeObject(forKey: "restEnd")
    }

    // MARK: tick

    private func saveStats() {
        if let d = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(d, forKey: "stats") }
    }

    // Night: the night block is locked until morning, once per night; nothing is asked.
    // A session that's already running just finishes.
    private func enterNightIfNeeded() {
        if pendingStart?.auto == true { cancelPick() }
        let end = nightEnd(after: now)
        if let applied = UserDefaults.standard.object(forKey: "nightUntil") as? Date, applied >= end { return }
        let mins = Int((end.timeIntervalSince(now) / 60).rounded(.up))
        runCT(["-start", S.nightBlock, "-lock", String(mins)], keep: Double(mins * 60 + 60))
        UserDefaults.standard.set(end, forKey: "nightUntil")
        log("night \(S.nightBlock) until \(clockLabel(S.nightTo)) (lock \(mins)m)")
        notify("Night mode", "\(S.nightBlock) is on until \(clockLabel(S.nightTo)). Time to sleep 🌙")
    }

    private func tick() {
        now = Date()
        if stats.day != dayKey(now) { stats = DayStats(day: dayKey(now)) }
        defer { if Int(now.timeIntervalSince1970) % 10 == 0 { saveStats() } }

        let night = isNight(now)
        if night { enterNightIfNeeded() }

        if let s = session {
            guard let cur = s.current(at: now) else {
                log("done  \(s.block) (app)")
                runCT(["-stop", s.block])
                endSession()
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
            notify("Free time is over", "Pick what's next.")
            return
        }

        // Nothing running and it's not night: you always decide what's next, right away.
        // The picker can't be closed; nothing is blocked until you pick.
        guard !night, review == nil, pendingStart == nil, userPresent() else { return }
        pendingStart = PendingStart(block: focusBlock, phases: [Phase(isBreak: false, minutes: defaultMinutes)], extra: [], auto: true)
        NSSound(named: "Funk")?.play()
        log("ask   what's next")
        showPicker()
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
    if m < 60 { return "\(m)m" }
    return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
}
