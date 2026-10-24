import SwiftUI

// Icon and color for an activity: what its settings say, or a guess from its name.
struct ActivityStyle {
    let icon: String
    let color: Color

    static let colors: [(name: String, color: Color)] = [
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("red", .red),
        ("orange", .orange), ("brown", .brown), ("green", .green), ("mint", .mint), ("teal", .teal), ("gray", .gray),
    ]
    // Grouped by kind of activity, so the picker reads like a menu of what you might do.
    static let iconGroups: [(name: String, icons: [String])] = [
        ("Work", ["briefcase.fill", "laptopcomputer", "desktopcomputer", "chevron.left.forwardslash.chevron.right",
                  "terminal.fill", "doc.text.fill", "chart.bar.fill", "envelope.fill", "phone.fill", "tray.full.fill"]),
        ("Learning", ["graduationcap.fill", "book.fill", "books.vertical.fill", "character.book.closed.fill",
                      "textformat.abc", "brain", "lightbulb.fill", "globe"]),
        ("Creating", ["hammer.fill", "pencil", "paintbrush.fill", "camera.fill", "music.note", "guitars.fill",
                      "film.fill", "mic.fill"]),
        ("Body & home", ["figure.run", "dumbbell.fill", "heart.fill", "leaf.fill", "fork.knife", "house.fill",
                         "cart.fill", "person.2.wave.2.fill"]),
        ("Rest", ["cup.and.saucer.fill", "bed.double.fill", "gamecontroller.fill", "sparkles", "circle.fill"]),
    ]
    static let icons = iconGroups.flatMap(\.icons)

    // History can name activities that no longer exist; those get the guess.
    @MainActor static func of(_ name: String) -> ActivityStyle {
        Settings.current.activity(named: name).map(of) ?? guess(name)
    }

    static func of(_ a: ActivitySetting) -> ActivityStyle {
        let guessed = guess(a.name)
        return ActivityStyle(icon: a.icon ?? guessed.icon,
                             color: colors.first { $0.name == a.color }?.color ?? guessed.color)
    }

    // Matches whole words, so "AI" doesn't also catch "Email" or "Training".
    static func guess(_ name: String) -> ActivityStyle {
        let n = name.lowercased()
        let words = n.split { !$0.isLetter }.map(String.init)
        func word(_ w: String) -> Bool { words.contains(w) }
        func starts(_ w: String) -> Bool { words.contains { $0.hasPrefix(w) } }
        if n == "work" { return ActivityStyle(icon: "briefcase.fill", color: .blue) }
        if starts("arab") { return ActivityStyle(icon: "character.book.closed.fill", color: .green) }
        if word("ai") { return ActivityStyle(icon: "brain", color: .purple) }
        if starts("project") { return ActivityStyle(icon: "hammer.fill", color: .orange) }
        if starts("english") { return ActivityStyle(icon: "textformat.abc", color: .teal) }
        if n == "rest" { return ActivityStyle(icon: "cup.and.saucer.fill", color: .brown) }
        if starts("interview") { return ActivityStyle(icon: "person.2.wave.2.fill", color: .indigo) }
        if n == otherActivity.lowercased() { return ActivityStyle(icon: "ellipsis.circle.fill", color: .gray) }
        return ActivityStyle(icon: "circle.fill", color: .pink)
    }
}
