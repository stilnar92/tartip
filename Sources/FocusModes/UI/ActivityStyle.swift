import SwiftUI

// Icon and color for an activity, picked from its name.
struct ActivityStyle {
    let icon: String
    let color: Color

    static func of(_ name: String) -> ActivityStyle {
        let n = name.lowercased()
        if n == "work" { return ActivityStyle(icon: "briefcase.fill", color: .blue) }
        if n.contains("arab") { return ActivityStyle(icon: "character.book.closed.fill", color: .green) }
        if n.contains("ai") { return ActivityStyle(icon: "brain", color: .purple) }
        if n.contains("project") { return ActivityStyle(icon: "hammer.fill", color: .orange) }
        if n.contains("english") { return ActivityStyle(icon: "textformat.abc", color: .teal) }
        if n == "rest" { return ActivityStyle(icon: "cup.and.saucer.fill", color: .brown) }
        if n.contains("interview") { return ActivityStyle(icon: "person.2.wave.2.fill", color: .indigo) }
        if n == otherActivity.lowercased() { return ActivityStyle(icon: "ellipsis.circle.fill", color: .gray) }
        return ActivityStyle(icon: "circle.fill", color: .pink)
    }
}
