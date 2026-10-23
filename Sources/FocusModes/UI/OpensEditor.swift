import SwiftUI
import AppKit

// What an activity opens when its session starts: apps, links, and whether to stretch windows.
struct OpensEditor: View {
    @ObservedObject var m: Model
    let activity: ActivitySetting
    @State private var newLink = ""

    var body: some View {
        let c = activity.opens
        let id = activity.id
        let tint = ActivityStyle.of(activity).color
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Opens")
            HStack(spacing: 8) {
                ForEach(c.apps, id: \.self) { path in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable().frame(width: 30, height: 30)
                        .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .contextMenu {
                            Button("Remove", role: .destructive) { m.updateOpens(id) { $0.apps.removeAll { $0 == path } } }
                        }
                }
                Button { m.chooseApps(for: id) } label: {
                    Image(systemName: "plus.app")
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Add apps")
            }
            ForEach(c.urls, id: \.self) { u in
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(tint)
                    Text(u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { m.updateOpens(id) { $0.urls.removeAll { $0 == u } } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Paste a link and press Enter", text: $newLink)
                    .textFieldStyle(.plain)
                    .onSubmit(addLink)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .card(radius: 9)
            Toggle(isOn: Binding(get: { activity.opens.maximize },
                                 set: { v in m.updateOpens(id) { $0.maximize = v } })) {
                Text("Stretch windows to fill the screen").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.mini).tint(tint)
        }
    }

    private func addLink() {
        let l = newLink.trimmingCharacters(in: .whitespaces)
        newLink = ""
        guard !l.isEmpty else { return }
        m.updateOpens(activity.id) { if !$0.urls.contains(l) { $0.urls.append(l) } }
    }
}
