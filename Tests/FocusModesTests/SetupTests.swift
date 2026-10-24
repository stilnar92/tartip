import Foundation
import Testing
@testable import FocusModes

@Suite struct SetupTests {
    // A fresh defaults domain and an empty folder, both removed afterwards.
    private func sandbox(_ body: (UserDefaults, URL) throws -> Void) throws {
        let name = "FocusModesTests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { d.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        try body(d, dir)
    }

    @Test func newInstallIsPendingUntilDone() throws {
        try sandbox { d, dir in
            Setup.resolve(d, evidence: [dir.appendingPathComponent("settings.json")])
            #expect(Setup.isPending(d))
            Setup.markDone(d)
            #expect(!Setup.isPending(d))
        }
    }

    @Test func existingSettingsMeanNoSetup() throws {
        try sandbox { d, dir in
            let settings = dir.appendingPathComponent("settings.json")
            try Data("{}".utf8).write(to: settings)
            Setup.resolve(d, evidence: [settings])
            #expect(!Setup.isPending(d))
        }
    }

    @Test func savedStateMeansNoSetup() throws {
        try sandbox { d, dir in
            d.set(Data(), forKey: "state")
            Setup.resolve(d, evidence: [dir.appendingPathComponent("settings.json")])
            #expect(!Setup.isPending(d))
        }
    }

    // Decided once: settings.json written a second later doesn't turn a new install into an old one.
    @Test func verdictIsKept() throws {
        try sandbox { d, dir in
            let settings = dir.appendingPathComponent("settings.json")
            Setup.resolve(d, evidence: [settings])
            try Data("{}".utf8).write(to: settings)
            Setup.resolve(d, evidence: [settings])
            #expect(Setup.isPending(d))
        }
    }

    @Test func newInstallStartsWithNoActivities() {
        #expect(AppSettings().activities.isEmpty)
        let t = activityTemplates[0]
        let a = ActivitySetting(template: t)
        #expect(a.name == t.name && a.icon == t.icon && a.color == t.color && a.block == t.name)
    }
}
