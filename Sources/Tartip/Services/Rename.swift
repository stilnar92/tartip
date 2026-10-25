import Foundation

// Focus Modes was renamed Tartip, with a new bundle id and so a new defaults domain.
// On the first launch under the new id the saved state is carried over: a running session,
// block locks, setup and the settings-lock timer all survive, so the rename can't be a way out.
enum Rename {
    static let oldDomain = "com.user.focusmodes"

    static func carryOverState(_ d: UserDefaults = .standard) {
        guard d.string(forKey: "renamedFrom") == nil else { return }
        d.set(oldDomain, forKey: "renamedFrom")
        guard let old = d.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
        // macOS's own window and panel keys belong to the old app; skip them.
        let ours = old.filter { !$0.key.hasPrefix("NS") && !$0.key.hasPrefix("Apple") && !$0.key.hasPrefix("com.apple") }
        for (k, v) in ours where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        log("rename carried over \(ours.count) saved values from \(oldDomain)")
    }
}
