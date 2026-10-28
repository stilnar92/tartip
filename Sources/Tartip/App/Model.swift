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
    @Published private(set) var awayRecords: [AwayRecord]
    @Published private(set) var events: [Event] = []      // loaded for Stats

    let clock: Clock
    var onPhaseChange: ((AppPhase) -> Void)?

    private let blocker: Blocker
    private var lastPhaseIndex: Int?
    private var ticker: Task<Void, Never>?
    private var settingsSub: AnyCancellable?
    private let keepAwake = KeepAwake()
    private var lockSubs: [NSObjectProtocol] = []

    init(clock: Clock? = nil, blocker: Blocker = NativeBlocker.shared, state: StoredState = StateStore.load()) {
        self.clock = clock ?? Clock()
        self.blocker = blocker
        self.state = state
        records = loadRecords()
        awayRecords = loadAway()
        events = loadEvents()

        if self.state.minutes < Settings.current.minMinutes { self.state.minutes = Settings.current.defaultSessionMinutes }
        if let s = state.phase.session, Date() < s.end {
            // Restarted mid-session: make sure the block is on for the time that's left.
            blocker.lock(s.block, until: s.end)
            lastPhaseIndex = s.current(at: Date())?.index
        }
        // Settings edits refresh the panel and the activity list right away.
        settingsSub = Settings.shared.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        // Locking the screen or putting the Mac to sleep is stepping away; unlocking is coming back.
        let dnc = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        let on = { (center: NotificationCenter, name: Notification.Name, f: @escaping @MainActor (Model) -> Void) in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { f(self) } }
            }
        }
        lockSubs = [
            on(dnc, Notification.Name("com.apple.screenIsLocked")) { $0.wentAway(lock: false) },
            on(ws, NSWorkspace.willSleepNotification) { $0.wentAway(lock: false) },
            on(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.comeBack() },
            on(ws, NSWorkspace.didWakeNotification) { if !screenLocked() { $0.comeBack() } },
        ]
        if self.state.phase.awaySince != nil { keepAwake.on() }
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
    // The ones planned for today's weekday: what the Today list and "What's next?" offer.
    var todayActivities: [String] { activities.filter(limits.isToday) }

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
            recs.append(SessionRecord(start: s.shiftedStart, end: min(now, s.end), mode: s.block, planned: planned))
        }
        return Tartip.records(recs, since: from)
    }

    func secondsByActivity(since from: Date) -> [String: Int] {
        Tartip.secondsByActivity(recordsSince(from))
    }

    var limits: Limits {
        Limits(settings: Settings.current, today: recordsSince(roundStart), now: now)
    }

    // Today's round: 1 until the limits first start over.
    var roundNumber: Int { todaysRound?.number ?? 1 }
    // Where the limits count from: the start of the day, or of today's round.
    var roundStart: Date { todaysRound?.since ?? Calendar.current.startOfDay(for: now) }
    private var todaysRound: Round? { state.round.flatMap { $0.day == dayKey(now) ? $0 : nil } }

    // Today's waking hours: what can be picked when, and what actually ran so far.
    struct DayView {
        var from: Int
        var to: Int
        var anyTime: [String]      // planned today without hours: can be picked in every period
        var periods: [Period]      // the whole waking day, with the activities that have hours
        var actual: [PlanSlot]     // from waking up until now
        var now: Int?              // nil outside the waking day
    }

    var today: DayView {
        let s = Settings.current
        let w = wakingHours(s)
        // Minutes in the waking day's frame, which may run past midnight.
        let inDay = { (m: Int) in m < w.from && m + 1440 <= w.to ? m + 1440 : m }
        let nowM = inDay(minuteOfDay(now))
        let dayStart = Calendar.current.startOfDay(for: now)
        let done = recordsSince(dayStart).map { r -> PlanSlot in
            let start = inDay(minuteOfDay(r.start))
            return PlanSlot(start: start, end: start + max(1, r.seconds / 60),
                            activity: r.actual.first ?? r.planned ?? otherActivity)
        }
        // Time away, the stretch going on now included.
        let aways = (awayRecords + (phase.awaySince.map { [AwayRecord(start: $0, end: now)] } ?? []))
            .filter { $0.end > dayStart }
            .map { r -> PlanSlot in
                let start = inDay(minuteOfDay(max(r.start, dayStart)))
                return PlanSlot(start: start, end: start + max(1, Int(r.end.timeIntervalSince(max(r.start, dayStart))) / 60),
                                activity: nil, away: true)
            }
        let frees = freePieces.filter { $0.t.addingTimeInterval(Double($0.seconds ?? 0)) > dayStart }.map { e -> PlanSlot in
            let start = inDay(minuteOfDay(max(e.t, dayStart)))
            return PlanSlot(start: start, end: start + max(1, (e.seconds ?? 0) / 60), activity: nil, free: true)
        }
        let weekday = Calendar.current.component(.weekday, from: now)
        let anyTime = s.activities.filter { a in
            !a.name.isEmpty && a.isPlanned(onWeekday: weekday) && (a.fromMinute == nil || a.toMinute == nil || a.fromMinute == a.toMinute)
        }.map(\.name)
        let periods = merged(availability(s, weekday: weekday, from: w.from, to: w.to).map {
            Period(start: $0.start, end: $0.end, available: $0.available.filter { !anyTime.contains($0) })
        })
        return DayView(from: w.from, to: w.to, anyTime: anyTime, periods: periods,
                       actual: pastDay(done + aways + frees, from: w.from, until: min(nowM, w.to)),
                       now: nowM >= w.from && nowM < w.to ? nowM : nil)
    }

    // Nothing can start but some work is open and used up: its limits count from zero again.
    private func startRoundIfStuck() {
        guard limits.needsNewRound(todayActivities) else { return }
        state.round = Round(day: dayKey(now), number: roundNumber + 1, since: now)
        log("round \(roundNumber): limits start over")
        record(Event(t: now, type: "round", number: roundNumber))
    }

    // Time in sessions today, by the clock, counting the running one.
    var focusedToday: Int {
        secondsByActivity(since: Calendar.current.startOfDay(for: now)).values.reduce(0, +)
    }

    // Free time pieces, the running one included (as used so far).
    var freePieces: [Event] {
        var out = events.filter { $0.type == "free" }
        if case .freeTime(let start, let end) = phase {
            out.append(Event(t: start, type: "free", seconds: freeTimeElapsed, minutes: Int(end.timeIntervalSince(start)) / 60))
        }
        return out
    }

    func reloadRecords() {
        records = loadRecords()
        events = loadEvents()
    }

    // MARK: first-run setup

    // "Start" on Get started: the picked apps and sites go into every block that has nothing
    // yet (activities, night, "Other"); blocks that already have rules are kept.
    // From the next tick on, "What's next?" and the night lock work as usual.
    func finishSetup(base: BlockRule) {
        let rules = NativeBlocker.shared
        rules.load()   // blocks.json may have been imported while setup was open
        let names = blocksToFill(Settings.current, existing: rules.rules)
        for name in names { rules.update(name) { $0 = base } }
        Setup.markDone()
        log("setup blocks: \(base.apps.count) apps, \(base.web.count) sites → \(names.joined(separator: ", "))")
    }

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

    func chooseFiles(for activity: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let paths = panel.urls.map(\.path)
            self?.updateOpens(activity) { c in
                for p in paths where !c.files.contains(p) { c.files.append(p) }
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
    var autoStartActivity: String? { limits.autoPick(from: todayActivities) }

    // "What's next?" went unanswered: start an activity for the auto-start length.
    // The length chosen in the panel isn't changed.
    private func autoStart() {
        guard let activity = autoStartActivity else { return }
        log("auto  \(activity) after \(Settings.current.autoStartAfterMinutes)m unanswered")
        startNow(activity, phases: [Phase(isBreak: false, minutes: max(Settings.current.minMinutes, Settings.current.autoStartMinutes))],
                 auto: true)
    }

    private func startNow(_ activity: String, phases: [Phase], auto: Bool = false) {
        let extra = oneTimeLink.trimmingCharacters(in: .whitespaces)
        oneTimeLink = ""
        var s = Session(block: Settings.current.block(for: activity), phases: phases, start: Date(), planned: activity)
        s.auto = auto ? true : nil
        s.pickSeconds = pickSeconds
        start(s, extraURLs: extra.isEmpty ? [] : [extra])
    }

    // How long "What's next?" has been open; nil when the start didn't come from it.
    private var pickSeconds: Int? {
        guard phase == .picking, let since = state.pickingSince else { return nil }
        return max(0, Int(Date().timeIntervalSince(since)))
    }

    private func start(_ s: Session, extraURLs: [String]) {
        blocker.lock(s.block, until: s.end)
        message = ""
        let c = s.planned.flatMap { Settings.current.activity(named: $0)?.opens } ?? ModeConfig()
        let opensSomething = !c.isEmpty || !extraURLs.isEmpty
        if opensSomething && c.maximize && !axTrusted(prompt: true) {
            message = "Allow Tartip in Privacy & Security → Accessibility to resize windows."
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
        log("off   \(s.block) (app)")
        finish(s, ended: "stopped")
    }

    // The session is over: ask what was actually done (sessions under a minute are dropped).
    // Time away doesn't count: the record starts that much later.
    private func finish(_ s: Session, at end: Date = Date(), ended: String) {
        lastPhaseIndex = nil
        var r = SessionRecord(start: s.shiftedStart, end: min(end, s.end), mode: s.block, planned: s.planned)
        r.began = s.start
        r.plannedMinutes = s.totalMinutes
        r.rounds = s.workRounds > 1 ? s.workRounds : nil
        r.paused = s.paused > 0 ? s.paused : nil
        r.ended = ended
        r.auto = s.auto
        r.pickSeconds = s.pickSeconds
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

    // MARK: away from the computer (no length: until you're back)

    // "Step away": the screen locks, the Mac keeps running, a session pauses. Unlocking ends it.
    func stepAway() {
        wentAway(lock: true)
    }

    // Also when the screen locks or the Mac sleeps by itself. Free time just goes on (it's yours
    // to spend anywhere), and a question waiting for an answer waits.
    fileprivate func wentAway(lock: Bool) {
        let paused: Session?
        switch phase {
        case .session(let s): paused = s
        case .idle, .picking: paused = nil
        case .away:
            if lock { lockScreen() }
            return
        case .freeTime, .reviewing:     // the shortcut still locks; nothing pauses
            if lock { lockScreen() }
            return
        }
        state.phase = .away(since: now, paused: paused)
        state.pickingSince = nil
        keepAwake.on()
        log("away" + (paused.map { " (\($0.planned ?? $0.block) paused)" } ?? ""))
        if lock { lockScreen() }
    }

    // Back at the computer: a paused session goes on where it stopped, with its block moved
    // by the time away. Away longer than the limit ends it instead, as of when you left.
    func comeBack() {
        guard case .away(let since, let paused) = phase else { return }
        keepAwake.off()
        let away = max(0, Int(now.timeIntervalSince(since)))
        if away >= 60 {
            let r = AwayRecord(start: since, end: now)
            appendAway(r)
            awayRecords.append(r)
        }
        guard var s = paused else {
            state.phase = .idle
            log("back after \(minutesLabel(away / 60))")
            return
        }
        if away > Settings.current.maxAwayMinutes * 60 {
            log("back after \(minutesLabel(away / 60)): \(s.planned ?? s.block) ended when you left")
            finish(s, at: since, ended: "away")
            return
        }
        s.paused += away
        blocker.lock(s.block, until: s.end)
        state.phase = .session(s)
        log("back after \(minutesLabel(away / 60)): \(s.planned ?? s.block) until \(Fmt.clock.string(from: s.end))")
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
        guard case .freeTime(let start, let end) = phase else { return }
        let used = freeTimeElapsed
        let piece = Event(t: start, type: "free", seconds: used, minutes: Int(end.timeIntervalSince(start)) / 60)
        record(piece)
        events.append(piece)
        let today = dayKey(now)
        state.freeUsed = DayStats(day: today, free: (state.freeUsed.day == today ? state.freeUsed.free : 0) + used)
        state.phase = .idle
    }

    // MARK: tick

    private func tick() {
        clock.now = Date()
        let night = Settings.current.isNight(at: now)
        // Until first-run setup is done nothing is pushed: no night lock, no "What's next?".
        if night && !Setup.isPending { enterNightIfNeeded() }
        blocker.tick(now)

        switch phase {
        case .session(let s):
            guard let cur = s.current(at: now) else {
                log("done  \(s.block) (app)")
                notify("Focus: \(s.block)", "Session done 🎉")
                finish(s, ended: "done")
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
            startRoundIfStuck()   // the picker opened, then what was left closed or ran out
            if let at = autoStartAt, now >= at { autoStart() }
        case .reviewing:
            return
        case .away(let since, _):
            // The unlock went unheard (or the lock didn't happen): if you're at it, you're back.
            if now.timeIntervalSince(since) > 5 && !screenLocked() { comeBack() }
        case .idle:
            // Nothing running and it's not night: you always decide what's next, right away.
            // The picker can't be closed; nothing is blocked until you pick.
            // A day with nothing planned is a day off: nothing is pushed.
            guard !night, !Setup.isPending, !todayActivities.isEmpty, userPresent() else { return }
            startRoundIfStuck()
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
        notify("Night mode", "It's on until \(clockLabel(Settings.current.nightTo)). Time to sleep 🌙")
    }

    // MARK: display

    var menuTitle: String {
        if let end = freeTimeEnd { return "☕ " + countdown(to: end, from: now) }
        guard let s = session, let cur = s.current(at: now) else { return "🎯" }
        return (s.phases[cur.index].isBreak ? "☕ " : "🎯 ") + countdown(to: cur.end, from: now)
    }
}

func dayKey(_ d: Date) -> String { Fmt.dayKey.string(from: d) }
