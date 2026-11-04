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
    @Published private(set) var dailyTasks = DailyTaskStore.load() {
        didSet { if dailyTasks != oldValue { DailyTaskStore.save(dailyTasks) } }
    }

    func tasks(for activity: UUID, day: String) -> [ActivityTask] {
        dailyTasks.tasks(day: day, activity: activity)
    }

    func setTasks(_ tasks: [ActivityTask], for activity: UUID, day: String) {
        dailyTasks.set(tasks, day: day, activity: activity)
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

        if self.state.phase == .picking && (!Settings.current.has(.guidance) || Setup.isPending || Settings.current.isNight(at: Date())) {
            self.state.phase = .idle
            self.state.pickingSince = nil
        }
        if self.state.minutes < Settings.current.minMinutes { self.state.minutes = Settings.current.defaultSessionMinutes }
        if let s = state.phase.session, Date() < s.end, let cur = s.current(at: Date()) {
            // Restarted mid-session: make sure the block matches the phase that's running (off on a break).
            if s.policy.blocking && !s.phases[cur.index].isBreak { blocker.lock(s.block, until: cur.end) }
            lastPhaseIndex = cur.index
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
        if self.state.phase.awaySince != nil && Settings.current.has(.away) { keepAwake.on() }
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
    var stepAwayUntil: Date? { state.stepAwayUntil }
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
        get { Settings.current.has(.pomodoro) && state.pomodoro }
        set { state.pomodoro = newValue }
    }

    // Sessions since `from`, plus the running one (under its planned activity).
    func recordsSince(_ from: Date) -> [SessionRecord] {
        recordsSince(from, upTo: now)
    }

    // Sessions in [from, upTo), plus the running one if it falls in range.
    func recordsSince(_ from: Date, upTo: Date) -> [SessionRecord] {
        var recs = records
        if let s = session, let planned = s.planned {
            recs.append(SessionRecord(start: s.shiftedStart, end: min(now, s.end), mode: s.block, planned: planned))
        }
        return Tartip.records(recs, from: from, to: upTo)
    }

    func secondsByActivity(since from: Date) -> [String: Int] {
        Tartip.secondsByActivity(recordsSince(from))
    }

    func secondsByActivity(since from: Date, upTo: Date) -> [String: Int] {
        Tartip.secondsByActivity(recordsSince(from, upTo: upTo))
    }

    var limits: Limits {
        Limits(settings: Settings.current, today: recordsSince(roundStart), now: now, debts: state.catchUpDebts)
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
        var overcommitted: [String] // planned today, asking for more daily minutes than their hours can actually fit
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
        // Time away, the stretch going on now (or waiting for its answer) included.
        let current = phase.awaySince.map { AwayRecord(start: $0, end: now) }
            ?? phase.awayStretch.map { AwayRecord(start: $0.since, end: $0.back) }
        let aways = (awayRecords + (current.map { [$0] } ?? []))
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
            !a.name.isEmpty && a.isPlanned(onWeekday: weekday) && !a.hasSchedule
        }.map(\.name)
        let periods = merged(availability(s, weekday: weekday, from: w.from, to: w.to).map {
            Period(start: $0.start, end: $0.end, available: $0.available.filter { !anyTime.contains($0) })
        })
        let overcommitted = Set(overcommittedActivities(s, weekday: weekday) + overcommittedPeriods(s, weekday: weekday)).sorted()
        return DayView(from: w.from, to: w.to, anyTime: anyTime, periods: periods,
                       actual: pastDay(done + aways + frees, from: w.from, until: min(nowM, w.to)),
                       now: nowM >= w.from && nowM < w.to ? nowM : nil,
                       overcommitted: overcommitted)
    }

    // Nothing can start but some work is open and used up: its limits count from zero again.
    private func startRoundIfStuck() {
        guard limits.needsNewRound(todayActivities) else { return }
        state.round = Round(day: dayKey(now), number: roundNumber + 1, since: now)
        log("round \(roundNumber): limits start over")
        record(Event(t: now, type: "round", number: roundNumber))
    }

    // Missed windows (today's and yesterday's) become debts, exactly once each per (activity,
    // day) — identity that stays stable even if the activity's hours are edited mid-day, so
    // this is safe to call redundantly from init and every tick, including the first tick
    // after a relaunch, which is what catches a window that closed while the app wasn't
    // running at all. An edit that moves the day's last window just updates windowEnd in
    // place on the existing debt, rather than opening a second one for the same day.
    // Debts past their one day of grace are force-expired.
    private func recomputeDebts() {
        let horizon = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        // From yesterday's midnight, not 24h back: yesterday is judged as a whole calendar day,
        // and a rolling window would drop its morning sessions as today goes on.
        let yesterdayStart = Calendar.current.startOfDay(for: horizon)
        // Only once no session is open: a running one counts just its elapsed part, which
        // would lock in a shortfall the rest of that session was about to cover.
        let missed = phase.hasOpenSession ? [] : missedWindows(Settings.current, records: recordsSince(yesterdayStart), now: now)
        for m in missed {
            // Already owed: only windowEnd (today's last-window edge) moves if hours were
            // edited mid-day — the shortfall itself is a snapshot, fixed at creation.
            if let i = state.catchUpDebts.firstIndex(where: { $0.activity == m.activity && $0.day == m.day }) {
                if state.catchUpDebts[i].settledAt == nil { state.catchUpDebts[i].windowEnd = m.windowEnd }
                continue
            }
            state.catchUpDebts.append(CatchUpDebt(activity: m.activity, day: m.day, windowEnd: m.windowEnd, catchUpMinutes: m.shortfall))
            log("catchup owed: \(m.activity) \(m.shortfall)m (missed \(m.day))")
        }
        let today = dayKey(now)
        let yesterday = dayKey(horizon)
        for i in state.catchUpDebts.indices {
            let d = state.catchUpDebts[i]
            guard d.settledAt == nil, !d.expired, d.day != today, d.day != yesterday else { continue }
            state.catchUpDebts[i].expired = true
            log("catchup expired: \(d.activity) (missed \(d.day))")
        }
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

    // MARK: what each activity opens

    func updateOpens(_ activity: UUID, _ change: (inout ModeConfig) -> Void) {
        Settings.shared.updateActivity(activity) { change(&$0.opens) }
        // Stretching windows needs Accessibility; ask as soon as there's something to stretch.
        if Settings.current.has(.workspace) && Settings.current.activities.contains(where: { $0.id == activity && $0.opens.maximize && !$0.opens.isEmpty }) { _ = axTrusted(prompt: true) }
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
    // A debt owed by this activity overrides the chosen length: catch-up sessions are always
    // the day's shortfall (catchUpMinutes minus whatever was already done), never the full
    // original window.
    func startActivity(_ activity: String, minutes chosen: Int? = nil, pomodoro usePomodoro: Bool? = nil) {
        guard !Setup.isPending, !Settings.current.isNight(at: now), activities.contains(activity), phase.canStart, limits.canStart(activity) else { return }
        if let debt = limits.owedDebt, debt.activity == activity {
            startNow(activity, phases: [Phase(isBreak: false, minutes: debt.catchUpMinutes)], settles: debt.id)
            return
        }
        if let chosen { minutes = chosen }
        if let usePomodoro { pomodoro = usePomodoro }
        if minutes < Settings.current.minMinutes { minutes = Settings.current.minMinutes }
        startNow(activity, phases: pomodoro ? Settings.current.pomodoroPhases() : [Phase(isBreak: false, minutes: minutes)])
    }

    // When auto-start fires, and which activity it would pick right now.
    var autoStartAt: Date? {
        guard Settings.current.has(.guidance), phase == .picking, Settings.current.autoStartAfterMinutes > 0, let since = state.pickingSince else { return nil }
        return since.addingTimeInterval(Double(Settings.current.autoStartAfterMinutes * 60))
    }
    var autoStartActivity: String? { limits.autoPick(from: todayActivities) }

    // "What's next?" went unanswered: start an activity for the auto-start length, or (if one
    // is owed) a debt's own fixed catch-up length — autoPick already restricts the choice to
    // the owed activity via Limits.canStart, so only the length needs the debt check here.
    private func autoStart() {
        guard let activity = autoStartActivity else { return }
        log("auto  \(activity) after \(Settings.current.autoStartAfterMinutes)m unanswered")
        if let debt = limits.owedDebt, debt.activity == activity {
            startNow(activity, phases: [Phase(isBreak: false, minutes: debt.catchUpMinutes)], auto: true, settles: debt.id)
            return
        }
        startNow(activity, phases: [Phase(isBreak: false, minutes: max(Settings.current.minMinutes, Settings.current.autoStartMinutes))],
                 auto: true)
    }

    private func startNow(_ activity: String, phases: [Phase], auto: Bool = false, settles: UUID? = nil) {
        let extra = Settings.current.has(.workspace) ? oneTimeLink.trimmingCharacters(in: .whitespaces) : ""
        oneTimeLink = ""
        var s = Session(block: Settings.current.block(for: activity), phases: phases, start: Date(), planned: activity)
        s.policy = SessionPolicy(settings: Settings.current)
        s.maxDurationSeconds = limits.sessionSeconds(activity, requested: s.totalMinutes * 60)
        s.auto = auto ? true : nil
        s.settles = settles
        s.pickSeconds = pickSeconds
        start(s, extraURLs: extra.isEmpty ? [] : [extra])
    }

    // How long "What's next?" has been open; nil when the start didn't come from it.
    private var pickSeconds: Int? {
        guard phase == .picking, let since = state.pickingSince else { return nil }
        return max(0, Int(Date().timeIntervalSince(since)))
    }

    private func start(_ s: Session, extraURLs: [String]) {
        if s.policy.blocking, let cur = s.current(at: Date()) { blocker.lock(s.block, until: cur.end) }
        message = ""
        if Settings.current.has(.workspace) {
            let c = s.planned.flatMap { Settings.current.activity(named: $0)?.opens } ?? ModeConfig()
            let opensSomething = !c.isEmpty || !extraURLs.isEmpty
            if opensSomething && c.maximize && !axTrusted(prompt: true) {
                message = "Allow Tartip in Privacy & Security → Accessibility to resize windows."
            }
            openWorkspace(mode: s.block, c, extraURLs: extraURLs, prev: state.opened) { [weak self] opened in
                self?.state.opened = opened
            }
        }

        state.restTaken = false
        state.phase = .session(s)
        lastPhaseIndex = 0
        let first = s.phases.first?.minutes ?? s.totalMinutes
        let desc = s.workRounds > 1 ? "pomodoro \(first)/\(Settings.current.pomodoroBreak)x\(s.workRounds)" : "\(s.totalMinutes)m"
        log("start \(s.block) (app, \(desc), lock \(s.totalMinutes)m)")
        let actualDuration = formatDuration(Int(s.end.timeIntervalSince(s.shiftedStart)))
        notify("Focus: \(s.block)", "\(actualDuration). Go!")
    }

    // "End session": over now, block lifted (whatever comes next brings its own), then the
    // usual review and "What's next?". Switching to something else midway is recorded as
    // what you actually did, and you can start the planned activity again afterwards.
    func endSession() {
        guard let s = session else { return }
        if s.policy.blocking { blocker.unlock(s.block) }
        log("end   \(s.planned ?? s.block) early, after \(minutesLabel(max(0, Int(now.timeIntervalSince(s.shiftedStart))) / 60))")
        finish(s, ended: "stopped")
    }

    // The session is over: ask what was actually done (sessions under a minute are dropped).
    // Time away doesn't count: the record starts that much later.
    private func finish(_ s: Session, at end: Date = Date(), ended: String) {
        lastPhaseIndex = nil
        if let r = s.completedRecord(at: end, ended: ended) {
            // History may have been written immediately before a process exit, while
            // the saved phase still points at this session. Do not append it twice.
            if records.contains(where: { $0.isSameSession(as: r) }) { state.phase = .idle; return }
            if s.policy.review { state.phase = .reviewing(r); return }
            payDebt(r)
            state.pendingRecords = (state.pendingRecords ?? []) + [r]
        }
        state.phase = .idle
        flushPendingRecords()
    }

    // Persist the outbox before leaving a session. Retrying after a restart is
    // idempotent even if history was appended just before the process exited.
    private func flushPendingRecords() {
        while let r = state.pendingRecords?.first {
            if !records.contains(where: { $0.isSameSession(as: r) }) {
                guard appendRecord(r) else {
                    message = "Session saved for retry. Could not write history yet."
                    return
                }
                records.append(r)
            }
            state.pendingRecords?.removeFirst()
        }
        if state.pendingRecords != nil { state.pendingRecords = nil }
        if message == "Session saved for retry. Could not write history yet." { message = "" }
    }

    func saveReview(actual: [String], selectedTasks: Set<UUID> = [], otherWork: [String: String] = [:]) {
        guard var r = review, !actual.isEmpty else { return }
        r.actual = actual
        let completed = dailyTasks.complete(day: dayKey(r.began ?? r.start), activities: Settings.current.activities,
                                            actual: actual, selected: Settings.current.has(.tasks) ? selectedTasks : [], otherWork: Settings.current.has(.tasks) ? otherWork : [:])
        r.completedTasks = completed.isEmpty ? nil : completed
        payDebt(r)
        state.pendingRecords = (state.pendingRecords ?? []) + [r]
        state.phase = .idle
        flushPendingRecords()
        log("did   \(actual.joined(separator: ", "))\(r.asPlanned ? " (as planned)" : "")")
    }

    // Only a session started specifically to pay this debt settles it (stamped in startNow):
    // logging time for the activity some other, coincidental way never clears it. Without the
    // review this runs as the session finishes, so a debt still gets paid with the review off.
    private func payDebt(_ r: SessionRecord) {
        guard let id = r.settles, let i = state.catchUpDebts.firstIndex(where: { $0.id == id }) else { return }
        pay(&state.catchUpDebts[i], with: r, at: now)
        let d = state.catchUpDebts[i]
        log(d.settledAt != nil ? "catchup done: \(d.activity)" : "catchup partly done: \(d.activity), \(d.catchUpMinutes)m left")
    }

    // MARK: away from the computer (no length: until you're back)

    // "Step away": the screen locks, the Mac keeps running, a session pauses. Unlocking ends it,
    // unless a minimum is set: then an early return just re-locks until it's actually elapsed.
    func stepAway() {
        guard Settings.current.has(.away) else { return }
        if Settings.current.stepAwayMinutes > 0 { state.stepAwayUntil = now.addingTimeInterval(Double(Settings.current.stepAwayMinutes * 60)) }
        wentAway(lock: true)
    }

    // Also when the screen locks or the Mac sleeps by itself. Free time just goes on (it's yours
    // to spend anywhere), and a question waiting for an answer waits.
    fileprivate func wentAway(lock: Bool) {
        let paused: Session?
        switch phase {
        case .session(let s): paused = s
        case .idle, .picking:
            guard Settings.current.has(.away) else { return }
            paused = nil
        case .away, .forcedBreak:       // already away, or on a break that can't be skipped by leaving
            if lock { lockScreen() }
            return
        case .freeTime, .reviewing, .awayReview:   // the shortcut still locks; nothing pauses
            if lock { lockScreen() }
            return
        }
        state.phase = .away(since: now, paused: paused)
        state.pickingSince = nil
        if Settings.current.has(.away) { keepAwake.on() }
        log("away" + (paused.map { " (\($0.planned ?? $0.block) paused)" } ?? ""))
        if lock { lockScreen() }
    }

    // Back at the computer. Asking what you did (Rules → Step away) comes first, and whatever
    // was paused waits for the answer; otherwise it's straight back to it.
    func comeBack() {
        guard case .away(let since, let paused) = phase else { return }
        // A Step away with a minimum: back early just re-locks, staying away until it elapses.
        if let until = state.stepAwayUntil {
            if now < until { lockScreen(); return }
            state.stepAwayUntil = nil
        }
        keepAwake.off()
        let away = max(0, Int(now.timeIntervalSince(since)))
        if Settings.current.asksAboutAway(seconds: away) {
            state.phase = .awayReview(since: since, back: now, paused: paused)
            log("back after \(minutesLabel(away / 60)): asking what you did")
            return
        }
        returned(since: since, back: now, paused: paused)
    }

    // "What did you do while away?" answered: from the list, in your own words, or both.
    func saveAwayReview(did: [String], note: String) {
        guard case .awayReview(let since, let back, let paused) = phase else { return }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty || !note.isEmpty else { return }
        log("was   " + (did + (note.isEmpty ? [] : [note])).joined(separator: ", "))
        returned(since: since, back: back, paused: paused, did: did, note: note)
    }

    // The stretch away is saved, then a paused session goes on where it stopped, with its block
    // moved by the time away. Away longer than the limit ends it instead, as of when you left.
    // Time spent answering what you did counts as away too, so it doesn't eat into the session.
    private func returned(since: Date, back: Date, paused: Session?, did: [String] = [], note: String = "") {
        let away = max(0, Int(back.timeIntervalSince(since)))
        if away >= 60 {
            let r = AwayRecord(start: since, end: back, did: did.isEmpty ? nil : did, note: note.isEmpty ? nil : note)
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
        s.paused += max(0, Int(now.timeIntervalSince(since)))
        if s.policy.blocking, let cur = s.current(at: now), !s.phases[cur.index].isBreak {
            blocker.lock(s.block, until: cur.end)
        }
        lastPhaseIndex = s.current(at: now)?.index
        state.phase = .session(s)
        log("back after \(minutesLabel(away / 60)): \(s.planned ?? s.block) until \(Fmt.clock.string(from: s.end))")
    }

    // MARK: forced breaks (too long at the computer: step away, no other choice until the cooldown ends)

    // The only thing you can do on a forced break: lock the screen again.
    func stepAwayForBreak() {
        guard phase.forcedBreakUntil != nil else { return }
        lockScreen()
    }

    // Resets whenever you're not continuously at the computer, so only unbroken stretches count.
    private func updateActivePresence() {
        guard Settings.current.has(.forcedBreak), Settings.current.forceBreakAfterHours > 0 else {
            state.activeSince = nil
            return
        }
        switch phase {
        case .away, .forcedBreak, .reviewing, .awayReview:
            state.activeSince = nil
        default:
            if !userPresent() { state.activeSince = nil }
            else if state.activeSince == nil { state.activeSince = now }
        }
    }

    // Too long continuously at the computer: end whatever's running and force a break.
    // Not while away, already on a break, or a question is waiting for an answer (reviewing).
    private func enterForcedBreakIfDue() {
        guard Settings.current.has(.forcedBreak), Settings.current.forceBreakAfterHours > 0,
              let since = state.activeSince,
              now.timeIntervalSince(since) >= Double(Settings.current.forceBreakAfterHours) * 3600
        else { return }
        switch phase {
        case .away, .forcedBreak, .reviewing, .awayReview: return
        case .session(let s): finish(s, ended: "forcedBreak")
        case .idle, .picking, .freeTime: break
        }
        state.pickingSince = nil
        state.activeSince = nil
        let until = now.addingTimeInterval(Double(Settings.current.forceBreakCooldownMinutes) * 60)
        state.phase = .forcedBreak(until: until)
        log("break forced after \(Settings.current.forceBreakAfterHours)h at the computer")
        lockScreen()
    }

    // MARK: free time (nothing blocked, only taken on purpose)
    //
    // Two tiers: up to `alwaysFreeMinutes` is always available after a session, outside the
    // daily budget. A longer stretch (up to `maxRestMinutes`) draws from the daily budget and
    // can only be picked once every `extendedFreeIntervalHours`.

    var freeLeft: Int { max(0, Settings.current.dailyFreeSeconds - freeUsedToday - freeTimeElapsed) }

    // Free time can't be taken twice in a row: a session has to run in between.
    var canRest: Bool { Settings.current.has(.guidance) && !state.restTaken }

    // Whether a stretch longer than `alwaysFreeMinutes` can be picked right now.
    var canExtendFree: Bool {
        Settings.current.freeTimeLengths.isEmpty == false && freeLeft >= 60 && isExtendedFreeDue
    }

    private var isExtendedFreeDue: Bool {
        guard let last = state.lastExtendedFreeAt else { return true }
        return now.timeIntervalSince(last) >= Double(Settings.current.extendedFreeIntervalHours) * 3600
    }

    // When the hourly allowance for a longer stretch becomes available again; nil if it is now.
    var extendedFreeAvailableAt: Date? {
        guard let last = state.lastExtendedFreeAt else { return nil }
        let at = last.addingTimeInterval(Double(Settings.current.extendedFreeIntervalHours) * 3600)
        return at > now ? at : nil
    }

    private var freeUsedToday: Int { state.freeUsed.day == dayKey(now) ? state.freeUsed.free : 0 }

    // The running free time so far; it's added to freeUsed when it ends.
    private var freeTimeElapsed: Int {
        guard case .freeTime(let start, let end) = phase else { return 0 }
        return max(0, Int(min(now, end).timeIntervalSince(start)))
    }

    func startRest(minutes: Int) {
        guard !Setup.isPending, !Settings.current.isNight(at: now), phase.canStart, canRest else { return }
        let start = Date()
        let secs: Int
        if minutes <= Settings.current.alwaysFreeMinutes {
            secs = minutes * 60   // always available: doesn't touch the daily budget
        } else {
            guard canExtendFree else { return }
            secs = min(min(minutes, Settings.current.maxRestMinutes) * 60, freeLeft)   // one stretch is capped (Settings)
            state.lastExtendedFreeAt = start
        }
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
        if state.lastExtendedFreeAt == start {   // the always-free tier doesn't touch the daily budget
            let today = dayKey(now)
            state.freeUsed = DayStats(day: today, free: (state.freeUsed.day == today ? state.freeUsed.free : 0) + used)
        }
        state.phase = .idle
    }

    // MARK: tick

    private func tick() {
        clock.now = Date()
        flushPendingRecords()
        if !Settings.current.has(.away) { keepAwake.off() }
        if Settings.current.has(.scheduling) && Settings.current.has(.catchUp) { recomputeDebts() }
        let night = Settings.current.isNight(at: now)
        // Until first-run setup is done nothing is pushed: no night lock, no "What's next?".
        if night && !Setup.isPending { enterNightIfNeeded() }
        blocker.tick(now)
        updateActivePresence()
        enterForcedBreakIfDue()

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
                if p.isBreak {
                    if s.policy.blocking { blocker.unlock(s.block) }
                    notify("Break \(p.minutes) min", "Blocking is off. Next round starts automatically.")
                } else {
                    if s.policy.blocking { blocker.lock(s.block, until: cur.end) }
                    notify("Round \(s.round(of: cur.index))/\(s.workRounds)", "\(p.minutes) min. Back to work!")
                }
            }
        case .freeTime(_, let end):
            guard now >= end else { return }
            endRest()
            notify("Free time is over", "Pick what's next.")
        case .picking:
            guard Settings.current.has(.guidance), !Setup.isPending else {
                state.pickingSince = nil
                state.phase = .idle
                return
            }
            if state.pickingSince == nil { state.pickingSince = now }
            startRoundIfStuck()   // the picker opened, then what was left closed or ran out
            if let at = autoStartAt, now >= at { autoStart() }
        case .reviewing, .awayReview:
            return
        case .away(let since, _):
            // The unlock went unheard (or the lock didn't happen): if you're at it, you're back.
            if now.timeIntervalSince(since) > 5 && !screenLocked() { comeBack() }
        case .forcedBreak(let until):
            // Coming back early changes nothing: only the cooldown running out ends the break.
            if now >= until { state.phase = .idle; log("break done, back to it") }
            else if !screenLocked() { lockScreen() }
        case .idle:
            // Nothing running and it's not night: you always decide what's next, right away.
            // The picker can't be closed; nothing is blocked until you pick.
            // A day with nothing planned is a day off: nothing is pushed.
            guard Settings.current.has(.guidance), !night, !Setup.isPending, !todayActivities.isEmpty, userPresent() else { return }
            startRoundIfStuck()
            // Day done: every limit reached and no free time to offer, so there's nothing to choose.
            let limits = limits
            guard activities.contains(where: limits.canStart) || canRest else { return }
            state.phase = .picking
            state.pickingSince = now
            if Settings.current.has(.notifications) { NSSound(named: "Funk")?.play() }
            log("ask   what's next")
        }
    }

    // Night: the night block is locked until morning, once per night; nothing is asked.
    // A session that's already running just finishes.
    private func enterNightIfNeeded() {
        if phase == .picking { state.phase = .idle }
        guard Settings.current.has(.blocking) else { return }
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
