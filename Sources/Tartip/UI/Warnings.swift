import SwiftUI
import AppKit

// What a commitment will do, in words, for the warnings shown before it starts:
// the person should know what gets closed and what can't be taken back.
@MainActor
enum Warnings {
    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.deletingPathExtension().lastPathComponent ?? bundleID
    }

    // "Closes Telegram and Discord. Blocks youtube.com, x.com and 5 more sites (except github.com)."
    static func blocks(_ r: BlockRule) -> String {
        var out: [String] = []
        if !r.apps.isEmpty { out.append("Closes " + andList(r.apps.map(appName), atMost: 4, more: "apps") + ".") }
        if !r.web.isEmpty {
            let sites = r.web == ["*"] ? "every site" : andList(r.web, atMost: 4, more: "sites")
            let except = r.exceptions.isEmpty ? "" : " (except " + andList(r.exceptions, atMost: 3) + ")"
            out.append("Blocks \(sites)\(except).")
        }
        return out.isEmpty ? "Its block has no apps or sites yet, so nothing gets closed." : out.joined(separator: " ")
    }

    // Asked on the first start of a block, and again whenever its rules change since then.
    // Every start would be a hurdle to starting, which is the one thing the app must not add.
    private static let seenKey = "acknowledgedBlocks"

    static func needsStartConfirm(block: String) -> Bool {
        seen()[block] != fingerprint(NativeBlocker.shared.rule(block))
    }

    static func acknowledge(block: String) {
        var s = seen()
        s[block] = fingerprint(NativeBlocker.shared.rule(block))
        UserDefaults.standard.set(s, forKey: seenKey)
    }

    private static func seen() -> [String: String] { UserDefaults.standard.dictionary(forKey: seenKey) as? [String: String] ?? [:] }

    private static func fingerprint(_ r: BlockRule) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(r)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func start(_ activity: String, minutes: Int) -> String {
        let block = Settings.current.block(for: activity)
        let until = Fmt.clock.string(from: Date().addingTimeInterval(Double(minutes * 60)))
        return blocks(NativeBlocker.shared.rule(block))
            + " This holds until \(until): stopping early ends the timer, not the block."
            + " You'll be asked again only if what \(activity) blocks changes."
    }

    static func night(_ s: AppSettings) -> String {
        "Every night from \(clockLabel(s.nightFrom)) to \(clockLabel(s.nightTo)) nothing is asked and \(s.nightBlock) stays locked. "
            + blocks(NativeBlocker.shared.rule(s.nightBlock))
            + " Once a night has started it can't be lifted until \(clockLabel(s.nightTo))."
    }

    static func lock(_ l: LockSettings) -> String {
        let looser = "you won't be able to remove activities or blocked apps and sites, cut days or hours, add free time, or turn night, auto-start or this lock off."
        switch l.mode {
        case .off:
            return ""
        case .afterChange:
            let span = l.hours < 24 ? "\(l.hours) hours" : l.hours == 24 ? "a day" : l.hours == 168 ? "a week" : "\(l.hours / 24) days"
            return "From 10 minutes after any change, for \(span), you can only make things stricter: \(looser) There's no way around it until it ends."
        case .hours:
            return "Outside \(clockLabel(l.from))–\(clockLabel(l.to)) you can only make things stricter: \(looser) There's no way around it until then."
        }
    }
}
