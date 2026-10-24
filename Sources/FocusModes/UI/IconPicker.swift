import SwiftUI

// An activity's icon button; clicking it opens a grid of icons grouped by kind of activity.
struct IconPicker: View {
    let icon: String
    let color: Color
    var size: CGFloat = 16
    let pick: (String) -> Void
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(color)
                .frame(width: size + 14, height: size + 14)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Choose an icon")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ActivityStyle.iconGroups, id: \.name) { group in
                    Text(group.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), alignment: .leading, spacing: 4) {
                        ForEach(group.icons, id: \.self) { i in
                            Button { pick(i); open = false } label: {
                                Image(systemName: i)
                                    .font(.system(size: 14))
                                    .foregroundStyle(i == icon ? .white : Theme.text)
                                    .frame(width: 30, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(i == icon ? color : Theme.pill))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .environment(\.colorScheme, .light)
        }
    }
}
