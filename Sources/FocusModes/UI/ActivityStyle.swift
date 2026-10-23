import SwiftUI

// Icon and color for an activity: what its settings say, or a guess from its name.
struct ActivityStyle {
    let icon: String
    let color: Color

    static let colors: [(name: String, color: Color)] = [
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("red", .red),
        ("orange", .orange), ("brown", .brown), ("green", .green), ("mint", .mint), ("teal", .teal), ("gray", .gray),
    ]
    static let icons = ["briefcase.fill", "laptopcomputer", "hammer.fill", "brain", "graduationcap.fill",
                        "character.book.closed.fill", "textformat.abc", "person.2.wave.2.fill", "cup.and.saucer.fill",
                        "figure.run", "music.note", "paintbrush.fill", "book.fill", "circle.fill"]

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
