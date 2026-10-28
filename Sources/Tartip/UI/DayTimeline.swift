import SwiftUI

// Today in two calendar columns on one time axis. Available: the day cut where an activity's
// hours start or end, each period shaded with the activities you can pick then (any-time ones
// are listed once above; red where nothing at all can start). Actual: the sessions that ran.
struct DayTimeline: View {
    let day: Model.DayView

    private let hourHeight: CGFloat = 56   // a 15-minute session still gets its label
    private let labelWidth: CGFloat = 40

    private func y(_ m: Int) -> CGFloat { CGFloat(m - day.from) / 60 * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !day.anyTime.isEmpty {
                (Text("Any time  ").foregroundColor(Theme.text2) + names(day.anyTime))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth, height: 1)
                title("Available", day.anyTime.isEmpty ? "what you can pick, by period" : "plus the any-time ones")
                title("Actual", "the sessions you ran")
            }
            HStack(alignment: .top, spacing: 8) {
                hourLabels
                column { w in
                    ForEach(Array(day.periods.enumerated()), id: \.offset) { i, p in
                        period(p, shade: i % 2 == 0).frame(width: w, height: max(2, y(p.end) - y(p.start) - 3)).offset(y: y(p.start) + 1.5)
                    }
                }
                column { w in
                    ForEach(Array(day.actual.enumerated()), id: \.offset) { _, s in
                        session(s).frame(width: w, height: max(2, y(s.end) - y(s.start) - 2)).offset(y: y(s.start) + 1)
                    }
                }
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

    // The axis marks where periods start and end: that's when what you can pick changes.
    private var hourMarks: [Int] { Array(Set(day.periods.flatMap { [$0.start, $0.end] } + [day.from, day.to])).sorted() }

    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourMarks, id: \.self) { m in
                Text(clockLabel(m % 1440)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .offset(y: y(m) - 6)
            }
        }
        .frame(width: labelWidth, height: y(day.to), alignment: .topLeading)
    }

    private func column<Content: View>(@ViewBuilder _ content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(hourMarks, id: \.self) { m in
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
        let label: Text = empty ? Text("Nothing can start").foregroundColor(Theme.red) : names(p.available)
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
