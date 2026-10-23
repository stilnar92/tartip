// Copies the session blocks from Cold Turkey into ~/modes/blocks.json, once.
// Run: swift scripts/import-cold-turkey.swift [--force]
//
// Cold Turkey keeps its settings in data-app.db, table settings, key "settings":
// "CTB" + a version digit + hex where every byte is shifted by +0x11. Decoded, it's JSON
// with blocks: {name: {apps: ["app:Telegram.app:com.tdesktop.telegram"], web: [...], exceptions: [...]}}.

import Foundation

let db = "/Library/Application Support/Cold Turkey/data-app.db"
let home = FileManager.default.homeDirectoryForCurrentUser
let out = home.appendingPathComponent("modes/blocks.json")
let force = CommandLine.arguments.contains("--force")

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

if FileManager.default.fileExists(atPath: out.path) && !force { fail("\(out.path) exists; use --force to replace it") }

// Session blocks: the ones the activities in settings.json lock, plus the night / "Other" block.
var names: [String] = []
if let d = try? Data(contentsOf: home.appendingPathComponent("modes/settings.json")),
   let s = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
    // Each activity locks its "block" (the name until it's set).
    names = ((s["activities"] as? [[String: Any]]) ?? []).compactMap { ($0["block"] as? String) ?? ($0["name"] as? String) }
    for key in ["nightBlock", "otherBlock"] { if let n = s[key] as? String { names.append(n) } }
}
if names.isEmpty { names = ["Focus_Mode"] }

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
p.arguments = ["-readonly", "file:\(db)?mode=ro", "select value from settings where key='settings';"]
let pipe = Pipe()
p.standardOutput = pipe
try p.run()
let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    .trimmingCharacters(in: .whitespacesAndNewlines)
p.waitUntilExit()
guard raw.hasPrefix("CTB"), let start = raw.range(of: "8C")?.lowerBound else { fail("unexpected settings format in \(db)") }

var bytes: [UInt8] = []
var i = start
while let j = raw.index(i, offsetBy: 2, limitedBy: raw.endIndex) {
    guard let b = UInt8(raw[i..<j], radix: 16) else { break }
    bytes.append(b &- 0x11)
    i = j
}
guard let json = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
      let blocks = json["blocks"] as? [String: [String: Any]] else { fail("couldn't decode Cold Turkey settings") }

var result: [String: [String: [String]]] = [:]
for name in Set(names) {
    guard let b = blocks[name] else { print("skip  \(name): no such Cold Turkey block"); continue }
    // "app:Telegram.app:com.tdesktop.telegram" → bundle id; "frozen:…" and file paths are skipped.
    let apps = ((b["apps"] as? [String]) ?? []).filter { $0.hasPrefix("app:") }.compactMap { $0.split(separator: ":").last.map(String.init) }
    result[name] = ["apps": apps, "web": (b["web"] as? [String]) ?? [], "exceptions": (b["exceptions"] as? [String]) ?? []]
    print("block \(name): \(apps.count) apps, \(result[name]!["web"]!.count) sites, \(result[name]!["exceptions"]!.count) exceptions")
}

let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: out)
print("Wrote \(out.path)")
