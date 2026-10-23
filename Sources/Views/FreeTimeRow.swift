import SwiftUI
import AppKit

// 🍿 Free time inside the picker: nothing blocked, from the daily budget.
// Not offered twice in a row, or when the budget is gone.
struct FreeTimeRow: View {
    @ObservedObject var m: Model

    var body: some View {
        let leftMin = m.freeLeft / 60
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "🍿 Free time · nothing blocked")
                Spacer()
                Text(m.restTaken ? "already taken · do a session first"
                                 : (leftMin > 0 ? "\(leftMin) min left today" : "used up today"))
                    .font(.system(size: 11)).foregroundStyle(m.canRest ? Color.secondary : Color.red)
            }
            HStack(spacing: 6) {
                ForEach(restOptions, id: \.self) { n in
                    let ok = m.canRest && m.freeLeft >= n * 60
                    Button { m.startRest(minutes: n) } label: {
                        Text(n >= 60 && n % 60 == 0 ? "\(n / 60) h" : "\(n) min")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.quaternary.opacity(0.6)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ok)
                    .opacity(ok ? 1 : 0.35)
                }
            }
        }
    }
}
