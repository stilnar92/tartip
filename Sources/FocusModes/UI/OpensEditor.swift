import SwiftUI
import AppKit

// What an activity opens when its session starts: apps, links, and whether to stretch windows.
struct OpensEditor: View {
    @ObservedObject var model: Model
    let activity: ActivitySetting
    @State private var newLink = ""

    var body: some View {
        let c = activity.opens
        let id = activity.id
        let tint = ActivityStyle.of(activity).color
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Opens")
            Text("Apps and links to open when it starts, so you land straight in the work.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(c.apps, id: \.self) { path in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable().frame(width: 30, height: 30)
                        .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .contextMenu {
                            Button("Remove", role: .destructive) { model.updateOpens(id) { $0.apps.removeAll { $0 == path } } }
                        }
                }
                Button { model.chooseApps(for: id) } label: {
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
                    Button { model.updateOpens(id) { $0.urls.removeAll { $0 == u } } } label: {
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
            // Only means something once there's an app or link to open.
            if !activity.opens.isEmpty {
                Toggle(isOn: Binding(get: { activity.opens.maximize },
                                     set: { v in model.updateOpens(id) { $0.maximize = v } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open them full size").font(.system(size: 12))
                        Text("Each window fills the screen, so only the work is in front of you. Needs Accessibility.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).controlSize(.mini).tint(tint)
            }
        }
    }

    private func addLink() {
        let l = newLink.trimmingCharacters(in: .whitespaces)
        newLink = ""
        guard !l.isEmpty else { return }
        model.updateOpens(activity.id) { if !$0.urls.contains(l) { $0.urls.append(l) } }
    }
}
