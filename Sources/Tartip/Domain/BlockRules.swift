// What a block blocks, and the URL matching rule (the same one Cold Turkey's extension uses).

import Foundation

// One block in ~/modes/blocks.json, named like the activity.
struct BlockRule: Codable, Equatable, Sendable {
    var apps: [String] = []         // bundle ids, quit while the block is on
    var web: [String] = []          // "google.com", "*", "instagram.com/reels*"
    var exceptions: [String] = []   // always allowed, even under "*"

    init(apps: [String] = [], web: [String] = [], exceptions: [String] = []) {
        self.apps = apps; self.web = web; self.exceptions = exceptions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        web = try c.decodeIfPresent([String].self, forKey: .web) ?? []
        exceptions = try c.decodeIfPresent([String].self, forKey: .exceptions) ?? []
    }

    // `edited` as far as it makes this rule stricter: apps and sites only added, exceptions only removed.
    func stricter(_ edited: BlockRule) -> BlockRule {
        BlockRule(apps: apps + edited.apps.filter { !apps.contains($0) },
                  web: web + edited.web.filter { !web.contains($0) },
                  exceptions: exceptions.filter { edited.exceptions.contains($0) })
    }

    // Exceptions win; then any web entry blocks. Browser pages (chrome://, about:) are never blocked.
    func blocks(url: String) -> Bool {
        let u = url.lowercased()
        if !(u.hasPrefix("http://") || u.hasPrefix("https://") || u.hasPrefix("file://")) { return false }
        if exceptions.contains(where: { urlMatches(u, $0) }) { return false }
        return web.contains { urlMatches(u, $0) }
    }
}

// "google.com" matches google.com and its subdomains with any path; "*" is a wildcard.
// A pattern with a scheme ("file://*.*") is matched against the whole URL.
func urlMatches(_ url: String, _ pattern: String) -> Bool {
    var p = pattern.trimmingCharacters(in: .whitespaces).lowercased()
    if p.isEmpty { return false }
    if p == "*" { return true }
    var u = url.lowercased()
    let escaped = { (s: String) in
        NSRegularExpression.escapedPattern(for: s).replacingOccurrences(of: "\\*", with: ".*")
    }
    let regex: String
    if p.contains("://") {
        regex = "^" + escaped(p) + "$"
    } else {
        for scheme in ["https://", "http://"] where u.hasPrefix(scheme) { u.removeFirst(scheme.count) }
        if u.hasPrefix("www.") { u.removeFirst(4) }
        if p.hasPrefix("www.") { p.removeFirst(4) }
        while p.hasSuffix("/") { p.removeLast() }
        regex = "^([^/?#]*\\.)?" + escaped(p) + "([/?#].*)?$"
    }
    return u.range(of: regex, options: .regularExpression) != nil
}
