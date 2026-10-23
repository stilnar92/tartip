import SwiftUI
import AppKit

// What a block stops while it's on: apps (quit) and sites (Chrome tabs go to a "Blocked" page).
// While it's locked you can only make it stricter: add apps and sites, remove exceptions.
struct BlockEditor: View {
    @ObservedObject var blocker = NativeBlocker.shared
    let block: String
    @State private var newSite = ""
    @State private var newException = ""

    var body: some View {
        let r = blocker.rule(block)
        let locked = blocker.isLocked(block)
        let tint = ActivityStyle.of(block).color
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Blocks")
                Spacer()
                if let until = blocker.locks[block], locked {
                    Label("locked until \(Fmt.clock.string(from: until))", systemImage: "lock.fill")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(r.apps, id: \.self) { id in
                    appIcon(id)
                        .contextMenu {
                            if !locked { Button("Remove", role: .destructive) { blocker.update(block) { $0.apps.removeAll { $0 == id } } } }
                        }
                }
                Button(action: chooseApps) {
                    Image(systemName: "plus.app")
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Apps to quit while this block is on")
            }
            entries("Sites", r.web, icon: "nosign", tint: tint, removable: !locked) { s in
                blocker.update(block) { $0.web.removeAll { $0 == s } }
            }
            addField("Block a site (google.com, * for all)", $newSite) { s in
                blocker.update(block) { if !$0.web.contains(s) { $0.web.append(s) } }
            }
            entries("Always allowed", r.exceptions, icon: "checkmark.circle", tint: .green, removable: true) { s in
                blocker.update(block) { $0.exceptions.removeAll { $0 == s } }
            }
            if !locked {
                addField("Allow a site (github.com, youtube.com/watch*)", $newException) { s in
                    blocker.update(block) { if !$0.exceptions.contains(s) { $0.exceptions.append(s) } }
                }
            }
        }
    }

    private func appIcon(_ id: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        return Group {
            if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable() }
            else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
        }
        .frame(width: 30, height: 30)
        .help(url?.deletingPathExtension().lastPathComponent ?? id)
    }

    @ViewBuilder
    private func entries(_ title: String, _ list: [String], icon: String, tint: Color, removable: Bool,
                         remove: @escaping (String) -> Void) -> some View {
        if !list.isEmpty {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(list, id: \.self) { s in
                    HStack(spacing: 5) {
                        Image(systemName: icon).foregroundStyle(tint).font(.system(size: 10))
                        Text(s).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if removable {
                            Button { remove(s) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func addField(_ prompt: String, _ text: Binding<String>, add: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .onSubmit {
                    let s = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                    text.wrappedValue = ""
                    if !s.isEmpty { add(s) }
                }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .card(radius: 9)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Block"
        NSApp.activate(ignoringOtherApps: true)
        // Not runModal: that would stall the run loop, and with it the timer.
        panel.begin { [blocker, block] response in
            guard response == .OK else { return }
            let ids = panel.urls.compactMap { bundleID($0.path) }
            blocker.update(block) { r in for id in ids where !r.apps.contains(id) { r.apps.append(id) } }
        }
    }

}
