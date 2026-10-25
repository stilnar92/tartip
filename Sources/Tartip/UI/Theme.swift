import SwiftUI

// Craft-like look: light lavender-white background, white cards with soft shadows
// instead of borders, grey pills, one blue accent, small grey tags.
enum Theme {
    static let bg = Color(red: 0.965, green: 0.965, blue: 0.98)          // #F6F6FA
    static let card = Color.white
    static let pill = Color(red: 0.925, green: 0.925, blue: 0.945)        // #ECECF1
    static let accent = Color(red: 0.18, green: 0.47, blue: 0.96)         // #2E78F5
    static let accentTint = Color(red: 0.89, green: 0.93, blue: 1.0)      // #E3EDFF
    static let text = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let text2 = Color(red: 0.54, green: 0.54, blue: 0.58)
    static let separator = Color.black.opacity(0.06)
    static let red = Color(red: 0.92, green: 0.26, blue: 0.32)
    static let redTint = Color(red: 1.0, green: 0.91, blue: 0.92)

    // Type scale.
    static let title = Font.system(size: 26, weight: .bold)      // page and window titles
    static let subtitle = Font.system(size: 13)                   // the line under a title
}

extension View {
    // No blue keyboard-focus ring: when a window opens, macOS puts focus on its first control
    // (Stop session, Stats…) and outlines it, which in a mouse-driven app reads as a glitch.
    // Tab still moves focus; only the outline goes.
    @ViewBuilder func noFocusRings() -> some View {
        if #available(macOS 14.0, *) { self.focusEffectDisabled() } else { self }
    }

    // White card with a soft shadow; a tint gives a light colored card with a thin edge.
    @ViewBuilder func card(_ tint: Color? = nil, radius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.map { AnyShapeStyle($0.opacity(0.10)) } ?? AnyShapeStyle(Theme.card))
                .shadow(color: .black.opacity(tint == nil ? 0.06 : 0), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint?.opacity(0.35) ?? Theme.separator, lineWidth: tint == nil ? 0.5 : 1)
        )
    }

    // Grey pill; selected = light blue with blue text (Craft's tabs).
    func pill(selected: Bool = false) -> some View {
        self.foregroundStyle(selected ? Theme.accent : Theme.text)
            .background(Capsule().fill(selected ? Theme.accentTint : Theme.pill))
            .contentShape(Capsule())
    }
}

// Small rounded tag, e.g. "1h left" or "from 12:00".
struct Tag: View {
    let text: String
    var color: Color = Theme.text2
    var fill: Color = Theme.pill

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}

// A page or window title with an optional line under it.
struct PageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.title).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(Theme.subtitle).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
