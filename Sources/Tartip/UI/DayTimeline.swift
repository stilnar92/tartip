import SwiftUI

// Today in calendar columns on one time axis: the plan (how the day can go with your hours
// and limits) next to what actually happened. Repeats are lighter; red is where nothing can start.
struct DayTimeline: View {
    struct Column {
        var title: String
        var slots: [PlanSlot]
    }

    let from: Int
    let to: Int
    let columns: [Column]
    var now: Int? = nil

    private let hourHeight: CGFloat = 56   // a 15-minute session still gets its label
    private let labelWidth: CGFloat = 40

    private func y(_ m: Int) -> CGFloat { CGFloat(m - from) / 60 * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(columns, id: \.title) { c in
                    Text(c.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                hourLabels
                ForEach(columns, id: \.title) { c in column(c.slots) }
            }
        }
    }

    // What the marks mean; only the ones this day uses.
    private var legend: some View {
        let all = columns.flatMap(\.slots)
        let has = { (f: (PlanSlot) -> Bool) in all.contains(where: f) }
        let items: [(String, AnyView)] = [
            has { !$0.done && $0.activity != nil && $0.round == 1 } ? ("Planned", AnyView(swatch(Theme.accent.opacity(0.2), edge: Theme.accent))) : nil,
            has { !$0.done && $0.round > 1 } ? ("↻ Again: nothing else is open", AnyView(swatch(Theme.accent.opacity(0.08), edge: Theme.accent.opacity(0.4)))) : nil,
            has { !$0.done && $0.activity == nil } ? ("Nothing can start", AnyView(swatch(Theme.redTint, dashed: Theme.red))) : nil,
            has { $0.done && $0.activity != nil } ? ("Done", AnyView(swatch(Theme.accent.opacity(0.85)))) : nil,
            has { $0.done && $0.activity == nil } ? ("No session", AnyView(swatch(Theme.pill))) : nil,
        ].compactMap { $0 }
        return FlowLayout(spacing: 12) {
            ForEach(items, id: \.0) { label, mark in
                HStack(spacing: 5) { mark; Text(label) }.font(.system(size: 10)).foregroundStyle(Theme.text2)
            }
        }
    }

    private func swatch(_ fill: Color, edge: Color? = nil, dashed: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 16, height: 11)
            .overlay(alignment: .leading) { if let edge { Rectangle().fill(edge).frame(width: 2.5) } }
            .overlay { if let dashed { RoundedRectangle(cornerRadius: 3).strokeBorder(dashed, style: StrokeStyle(lineWidth: 1, dash: [2, 2])) } }
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourMarks, id: \.self) { m in
                Text(clockLabel(m % 1440)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .offset(y: y(m) - 6)
            }
        }
        .frame(width: labelWidth, height: y(to), alignment: .topLeading)
    }

    private func column(_ slots: [PlanSlot]) -> some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(hourMarks, id: \.self) { m in
                    Rectangle().fill(Theme.separator).frame(width: g.size.width, height: 1).offset(y: y(m))
                }
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    block(slot).frame(width: g.size.width, height: max(2, y(slot.end) - y(slot.start) - 2))
                        .offset(y: y(slot.start) + 1)
                }
                if let now {
                    HStack(spacing: 0) {
                        Circle().fill(Theme.red).frame(width: 7, height: 7)
                        Rectangle().fill(Theme.red).frame(height: 1.5)
                    }
                    .frame(width: g.size.width).offset(y: y(now) - 3.5)
                }
            }
        }
        .frame(height: y(to))
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var hourMarks: [Int] {
        stride(from: (from + 59) / 60 * 60, through: to, by: 60).map { $0 }
    }

    @ViewBuilder private func block(_ slot: PlanSlot) -> some View {
        let h = y(slot.end) - y(slot.start)
        let tall = h >= 24        // room to sit at the top
        let fits = h >= 12        // room for one line at all
        if let name = slot.activity {
            let st = ActivityStyle.of(name)
            let repeat_ = slot.round > 1 && !slot.done
            HStack(spacing: 5) {
                Image(systemName: slot.done ? "checkmark" : (repeat_ ? "arrow.counterclockwise" : st.icon))
                    .font(.system(size: 10, weight: .semibold))
                Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(repeat_ ? "again · \(minutesLabel(slot.minutes))" : minutesLabel(slot.minutes))
                    .font(.system(size: 10)).opacity(0.8).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(slot.done ? .white : st.color)
            .padding(.horizontal, 7)
            .frame(maxHeight: .infinity, alignment: tall ? .top : .center)
            .padding(.top, tall ? 4 : 0)
            .opacity(fits ? 1 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(slot.done ? AnyShapeStyle(st.color.opacity(0.85)) : AnyShapeStyle(st.color.opacity(repeat_ ? 0.08 : 0.18)))
            )
            .overlay(alignment: .leading) {
                if !slot.done {
                    RoundedRectangle(cornerRadius: 2).fill(st.color.opacity(repeat_ ? 0.4 : 1)).frame(width: 3)
                }
            }
            .help("\(name) \(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440))"
                  + (slot.done ? ", done" : repeat_ ? ", again: its limit started over" : ""))
        } else if slot.done {
            Text("No session · \(minutesLabel(slot.minutes))")
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tall ? .topLeading : .leading)
                .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
                .opacity(fits ? 1 : 0)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.pill.opacity(0.6)))
                .help("\(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440)): no session ran")
        } else {
            Text("Nothing can start · \(minutesLabel(slot.minutes))")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tall ? .topLeading : .leading)
                .padding(.horizontal, 7).padding(.top, tall ? 4 : 0)
                .opacity(fits ? 1 : 0)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.redTint.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .help("\(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440)): no activity is open")
        }
    }
}

// The same day in one bar, for the panel: done, planned, repeats lighter, gaps red.
struct DayStrip: View {
    let from: Int
    let to: Int
    let slots: [PlanSlot]
    var now: Int? = nil

    var body: some View {
        let span = CGFloat(max(1, to - from))
        let gaps = slots.filter { $0.activity == nil && !$0.done }.map(\.minutes).reduce(0, +)
        let repeats = slots.filter { $0.activity != nil && $0.round > 1 && !$0.done }.map(\.minutes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Theme.pill).frame(width: g.size.width, height: 12)
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        segment(slot)
                            .frame(width: max(1.5, g.size.width * CGFloat(slot.minutes) / span - 1), height: 12)
                            .offset(x: g.size.width * CGFloat(slot.start - from) / span)
                    }
                    if let now {
                        Rectangle().fill(Theme.text).frame(width: 2, height: 18)
                            .offset(x: g.size.width * CGFloat(now - from) / span - 1, y: -3)
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 8) {
                Text(clockLabel(from % 1440))
                if gaps > 0 { Label(minutesLabel(gaps) + " nothing open", systemImage: "exclamationmark.circle").foregroundStyle(Theme.red) }
                if repeats > 0 { Label(minutesLabel(repeats) + " again", systemImage: "arrow.counterclockwise") }
                Spacer()
                Text(clockLabel(to % 1440))
            }
            .font(.system(size: 10)).foregroundStyle(Theme.text2)
        }
    }

    @ViewBuilder private func segment(_ slot: PlanSlot) -> some View {
        if let name = slot.activity {
            let c = ActivityStyle.of(name).color
            RoundedRectangle(cornerRadius: 2).fill(c.opacity(slot.done ? 0.9 : slot.round > 1 ? 0.25 : 0.55))
                .help("\(name) \(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440))")
        } else if slot.done {
            RoundedRectangle(cornerRadius: 2).fill(Theme.text2.opacity(0.2))
                .help("No session \(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440))")
        } else {
            RoundedRectangle(cornerRadius: 2).fill(Theme.red.opacity(0.55))
                .help("Nothing can start \(clockLabel(slot.start % 1440))–\(clockLabel(slot.end % 1440))")
        }
    }
}
