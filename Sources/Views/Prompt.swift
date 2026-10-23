import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Prompt window ("time to focus")

struct PromptView: View {
    @ObservedObject var m: Model

    var body: some View {
        let p = m.prompt
        let left = p.map { max(0, $0.deadline.timeIntervalSince(m.now)) } ?? 0
        let defaultBlock = m.focusBlock
        let tint = BlockStyle.of(defaultBlock).color

        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: left / promptCountdown)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                Text("\(Int(left.rounded(.up)))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 6) {
                Text(p?.kind.title ?? "")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Then you'll \(m.promptDefaultLabel)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }

            Button(action: m.promptDefault) {
                HStack(spacing: 8) {
                    Image(systemName: BlockStyle.of(defaultBlock).icon)
                    Text("Choose now")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.gradient))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            if m.blocks.count > 1 { VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Or pick a mode · \(m.pomodoro ? "Pomodoro" : "\(m.minutes) min")")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(m.blocks, id: \.self) { b in
                        let st = BlockStyle.of(b)
                        Button { m.startFromPrompt(b) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: st.icon).foregroundStyle(st.color)
                                Text(b.replacingOccurrences(of: "_", with: " ")).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .card(radius: 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } }

            RestPicker(m: m)
        }
        .padding(24)
        .frame(width: 400)
    }
}

// Rest chips + what's left today. Disabled when the budget is gone.
struct RestPicker: View {
    @ObservedObject var m: Model

    var body: some View {
        let leftMin = m.freeLeft / 60
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Free time · nothing blocked")
                Spacer()
                Text(m.restTaken ? "already used · start a mode first" : (leftMin > 0 ? "\(leftMin) min left today" : "used up today"))
                    .font(.system(size: 11)).foregroundStyle(m.canRest ? Color.secondary : Color.red)
            }
            HStack(spacing: 6) {
                ForEach(restOptions, id: \.self) { n in
                    let ok = m.canRest
                    Button { m.startRest(minutes: n) } label: {
                        Text("☕ \(min(n, max(leftMin, 1)))m")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.quaternary.opacity(0.6)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ok)
                    .opacity(ok ? 1 : 0.4)
                }
            }
        }
    }
}

struct TodayStats: View {
    @ObservedObject var m: Model

    var body: some View {
        HStack(spacing: 0) {
            stat("Focus", formatDuration(m.stats.focus), .indigo)
            stat("Free", "\(m.stats.free / 60)/\(dailyFreeSeconds / 60)m", m.freeLeft > 0 ? .green : .red)
        }
        .padding(.vertical, 8)
        .card(radius: 12)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
