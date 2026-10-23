import AppKit
import Combine

// The app's state and everything that changes it. Views read it; WindowCoordinator
// shows the "What's next?" and review windows when the phase asks for them.
@MainActor
final class Model: ObservableObject {
    @Published private(set) var state: StoredState {
        didSet {
            guard state != oldValue else { return }
            StateStore.save(state)
            if state.phase != oldValue.phase { onPhaseChange?(state.phase) }
        }
    }
    @Published var message = ""
    @Published var oneTimeLink = ""
    @Published private(set) var records: [SessionRecord]

    let clock: Clock
    var onPhaseChange: ((AppPhase) -> Void)?

    private let blocker: Blocker
    private var lastPhaseIndex: Int?
    private var ticker: Task<Void, Never>?
    private var settingsSub: AnyCancellable?

    init(clock: Clock? = nil, blocker: Blocker = ColdTurkey(), state: StoredState = StateStore.load()) {
        self.clock = clock ?? Clock()
        self.blocker = blocker
        self.state = state
        records = loadRecords()

        if self.state.minutes < Settings.current.minMinutes { self.state.minutes = Settings.current.defaultSessionMinutes }
        if let s = state.phase.session, Date() < s.end {
            // Restarted mid-session: make sure the block is on for the time that's left.
            blocker.lock(s.block, until: s.end)
            lastPhaseIndex = s.current(at: Date())?.index
        } else {
            blocker.clearStrayCommands()
        }
        // Settings edits refresh the panel and the activity list right away.
        settingsSub = Settings.shared.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    // MARK: reading the state

    var now: Date { clock.now }
    var phase: AppPhase { state.phase }
    var session: Session? { phase.session }
    var review: SessionRecord? { phase.review }
    var freeTimeEnd: Date? { phase.freeTimeEnd }
    var restTaken: Bool { state.restTaken }
    var activities: [String] { Settings.current.activities.map(\.name).filter { !$0.isEmpty } }

    // Length for the next start, kept across restarts.
    var minutes: Int {
        get { state.minutes }
        set { state.minutes = newValue }
    }
    var pomodoro: Bool {
        get { state.pomodoro }
        set { state.pomodoro = newValue }
    }

    // Sessions since `from`, plus the running one (under its planned activity).
    func recordsSince(_ from: Date) -> [SessionRecord] {
        var recs = records
        if let s = session, let planned = s.planned {
            recs.append(SessionRecord(start: s.start, end: min(now, s.end), mode: s.block, planned: planned))
        }
        return FocusModes.records(recs, since: from)
    }

    func secondsByActivity(since from: Date) -> [String: Int] {
        FocusModes.secondsByActivity(recordsSince(from))
    }

    var limits: Limits {
        Limits(settings: Settings.current, today: recordsSince(Calendar.current.startOfDay(for: now)), now: now)
    }

    // Time in sessions today, by the clock, counting the running one.
    var focusedToday: Int {
        secondsByActivity(since: Calendar.current.startOfDay(for: now)).values.reduce(0, +)
    }

    func reloadRecords() { records = loadRecords() }

    // MARK: what each activity opens

    func updateOpens(_ activity: UUID, _ change: (inout ModeConfig) -> Void) {
        Settings.shared.updateActivity(activity) { change(&$0.opens) }
        // Stretching windows needs Accessibility; ask as soon as there's something to stretch.
        if Settings.current.activities.contains(where: { $0.id == activity && !$0.opens.isEmpty }) { _ = axTrusted(prompt: true) }
    }

    func chooseApps(for activity: UUID) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        // Not runModal: that would stall the run loop, and with it the timer.
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let paths = panel.urls.map(\.path)
            self?.updateOpens(activity) { c in
                for p in paths where !c.apps.contains(p) { c.apps.append(p) }
            }
        }
    }

    // MARK: sessions

    // One click on a row in the Today list: start it now with the chosen length (or Pomodoro).
    func startActivity(_ activity: String, minutes chosen: Int? = nil, pomodoro usePomodoro: Bool? = nil) {
        guard phase.canStart, limits.canStart(activity) else { return }
        if let chosen { minutes = chosen }
        if let usePomodoro { pomodoro = usePomodoro }
        if minutes < Settings.current.minMinutes { minutes = Settings.current.minMinutes }
        startNow(activity, phases: pomodoro ? Settings.current.pomodoroPhases() : [Phase(isBreak: false, minutes: minutes)])
    }

    // When auto-start fires, and which activity it would pick right now.
    var autoStartAt: Date? {
        guard phase == .picking, Settings.current.autoStartAfterMinutes > 0, let since = state.pickingSince else { return nil }
        return since.addingTimeInterval(Double(Settings.current.autoStartAfterMinutes * 60))
    }
    var autoStartActivity: String? { limits.autoPick(from: activities) }

    // "What's next?" went unanswered: start an activity for the auto-start length.
    // The length chosen in the panel isn't changed.
    private func autoStart() {
        guard let activity = autoStartActivity else { return }
        log("auto  \(activity) after \(Settings.current.autoStartAfterMinutes)m unanswered")
        startNow(activity, phases: [Phase(isBreak: false, minutes: max(Settings.current.minMinutes, Settings.current.autoStartMinutes))])
    }

    private func startNow(_ activity: String, phases: [Phase]) {
        let extra = oneTimeLink.trimmingCharacters(in: .whitespaces)
        oneTimeLink = ""
        start(Session(block: Settings.current.block(for: activity), phases: phases, start: Date(), planned: activity),
              extraURLs: extra.isEmpty ? [] : [extra])
    }

    private func start(_ s: Session, extraURLs: [String]) {
        blocker.lock(s.block, until: s.end)
        message = ""
        let c = s.planned.flatMap { Settings.current.activity(named: $0)?.opens } ?? ModeConfig()
        let opensSomething = !c.isEmpty || !extraURLs.isEmpty
        if opensSomething && c.maximize && !axTrusted(prompt: true) {
            message = "Allow Focus Modes in Privacy & Security → Accessibility to resize windows."
        }
        openWorkspace(mode: s.block, c, extraURLs: extraURLs, prev: state.opened) { [weak self] opened in
            self?.state.opened = opened
        }

        state.restTaken = false
        state.phase = .session(s)
        lastPhaseIndex = 0
        let first = s.phases.first?.minutes ?? s.totalMinutes
        let desc = s.workRounds > 1 ? "pomodoro \(first)/\(Settings.current.pomodoroBreak)x\(s.workRounds)" : "\(s.totalMinutes)m"
        log("start \(s.block) (app, \(desc), lock \(s.totalMinutes)m)")
        notify("Focus: \(s.block)", s.workRounds > 1 ? "Round 1/\(s.workRounds) — \(first) min. Go!" : "\(s.totalMinutes) min. Go!")
    }

    func stop() {
        guard let s = session else { return }
        if Date() < s.end {
            message = "Locked until \(Fmt.clock.string(from: s.end)). Timer stopped, block stays."
        }
        blocker.stop(s.block)
        log("off   \(s.block) (app)")
        finish(s)
    }

    // The session is over: ask what was actually done (sessions under a minute are dropped).
    private func finish(_ s: Session) {
        lastPhaseIndex = nil
        let r = SessionRecord(start: s.start, end: min(Date(), s.end), mode: s.block, planned: s.planned)
        state.phase = r.seconds >= 60 ? .reviewing(r) : .idle
    }

    func saveReview(actual: [String]) {
        guard var r = review else { return }
        r.actual = actual
        appendRecord(r)
        records.append(r)
        state.phase = .idle
        log("did   \(actual.joined(separator: ", "))\(r.asPlanned ? " (as planned)" : "")")
    }

    // MARK: free time (nothing blocked, from the daily budget, only taken on purpose)

    var freeLeft: Int { max(0, Settings.current.dailyFreeSeconds - freeUsedToday - freeTimeElapsed) }

    // Free time can't be taken twice in a row: a session has to run in between.
    var canRest: Bool { freeLeft >= 60 && !state.restTaken }

    private var freeUsedToday: Int { state.freeUsed.day == dayKey(now) ? state.freeUsed.free : 0 }

    // The running free time so far; it's added to freeUsed when it ends.
    private var freeTimeElapsed: Int {
        guard case .freeTime(let start, let end) = phase else { return 0 }
        return max(0, Int(min(now, end).timeIntervalSince(start)))
    }

    func startRest(minutes: Int) {
        guard phase.canStart, canRest else { return }
        let secs = min(min(minutes, Settings.current.maxRestMinutes) * 60, freeLeft)   // one stretch is capped (Settings)
        let start = Date()
        state.restTaken = true
        state.phase = .freeTime(start: start, end: start.addingTimeInterval(Double(secs)))
        log("rest  \(secs / 60)m (\(freeLeft / 60)m left today)")
    }

    func endRest() {
        guard case .freeTime = phase else { return }
        let used = freeTimeElapsed
        let today = dayKey(now)
        state.freeUsed = DayStats(day: today, free: (state.freeUsed.day == today ? state.freeUsed.free : 0) + used)
        state.phase = .idle
    }

    // MARK: tick

    private func tick() {
        clock.now = Date()
        let night = Settings.current.isNight(at: now)
        if night { enterNightIfNeeded() }

        switch phase {
        case .session(let s):
            guard let cur = s.current(at: now) else {
                log("done  \(s.block) (app)")
                blocker.stop(s.block)
                notify("Focus: \(s.block)", "Session done 🎉")
                finish(s)
                return
            }
            if cur.index != lastPhaseIndex {
                lastPhaseIndex = cur.index
                let p = s.phases[cur.index]
                if p.isBreak { notify("Break \(p.minutes) min", "Stand up, drink water. Next round starts automatically.") }
                else { notify("Round \(s.round(of: cur.index))/\(s.workRounds)", "\(p.minutes) min. Back to work!") }
            }
        case .freeTime(_, let end):
            guard now >= end else { return }
            endRest()
            notify("Free time is over", "Pick what's next.")
        case .picking:
            if state.pickingSince == nil { state.pickingSince = now }
            if let at = autoStartAt, now >= at { autoStart() }
        case .reviewing:
            return
        case .idle:
            // Nothing running and it's not night: you always decide what's next, right away.
            // The picker can't be closed; nothing is blocked until you pick.
            guard !night, userPresent() else { return }
            // Day done: every limit reached and no free time to offer, so there's nothing to choose.
            let limits = limits
            guard activities.contains(where: limits.canStart) || canRest else { return }
            state.phase = .picking
            state.pickingSince = now
            NSSound(named: "Funk")?.play()
            log("ask   what's next")
        }
    }

    // Night: the night block is locked until morning, once per night; nothing is asked.
    // A session that's already running just finishes.
    private func enterNightIfNeeded() {
        if phase == .picking { state.phase = .idle }
        let end = Settings.current.nightEnd(after: now)
        if let applied = state.nightUntil, applied >= end { return }
        blocker.lock(Settings.current.nightBlock, until: end)
        state.nightUntil = end
        log("night \(Settings.current.nightBlock) until \(clockLabel(Settings.current.nightTo))")
        notify("Night mode", "\(Settings.current.nightBlock) is on until \(clockLabel(Settings.current.nightTo)). Time to sleep 🌙")
    }

    // MARK: display

    var menuTitle: String {
        if let end = freeTimeEnd { return "☕ " + countdown(to: end, from: now) }
        guard let s = session, let cur = s.current(at: now) else { return "🎯" }
        return (s.phases[cur.index].isBreak ? "☕ " : "🎯 ") + countdown(to: cur.end, from: now)
    }
}

func dayKey(_ d: Date) -> String { Fmt.dayKey.string(from: d) }
