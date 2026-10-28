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
        // A running block, or the settings lock: either way it can only get stricter.
        let sessionUntil = blocker.isLocked(block) ? blocker.locks[block] : nil
        let settingsUntil = Settings.shared.lockedUntil
        let locked = sessionUntil != nil || settingsUntil != nil
        let until = [sessionUntil, settingsUntil].compactMap { $0 }.max().map { Fmt.clock.string(from: $0) } ?? ""
        let why = sessionUntil != nil
            ? "On until \(until): you can add apps and sites now; removing them and allowing sites works again after."
            : "Settings are locked until \(until): only stricter changes for now."
        let tint = ActivityStyle.of(block).color
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Blocks")
            if locked {
                Label(why, systemImage: "lock.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
            entries("Sites", r.web, icon: "nosign", tint: tint, removable: !locked, heldWhy: why) { s in
                blocker.update(block) { $0.web.removeAll { $0 == s } }
            }
            addField("Block sites (google.com, x.com; * for all)", $newSite) { list in
                blocker.update(block) { r in for s in list where !r.web.contains(s) { r.web.append(s) } }
            }
            // Always shown: while locked the field stays, just disabled, so it's clear it's held, not gone.
            entries("Always allowed", r.exceptions, icon: "checkmark.circle", tint: .green, removable: true, heldWhy: why,
                    showEmpty: true) { s in
                blocker.update(block) { $0.exceptions.removeAll { $0 == s } }
            }
            addField(locked ? "Allowing sites works again after \(until)" : "Allow sites (github.com, youtube.com/watch*)",
                     $newException) { list in
                blocker.update(block) { r in for s in list where !r.exceptions.contains(s) { r.exceptions.append(s) } }
            }
            .disabled(locked)
            .opacity(locked ? 0.6 : 1)
            .help(locked ? why : "")
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
                         heldWhy: String = "", showEmpty: Bool = false, remove: @escaping (String) -> Void) -> some View {
        if !list.isEmpty || showEmpty {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if !list.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(list, id: \.self) { s in
                    HStack(spacing: 5) {
                        Image(systemName: icon).foregroundStyle(tint).font(.system(size: 10))
                        Text(s).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if removable {
                            Button { remove(s) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary).help(heldWhy)
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    // Takes one site or a list: separated by commas, spaces or new lines, as pasted.
    private func addField(_ prompt: String, _ text: Binding<String>, add: @escaping ([String]) -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .onSubmit {
                    let list = splitList(text.wrappedValue).map {
                        $0.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                    }
                    text.wrappedValue = ""
                    if !list.isEmpty { add(list) }
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
