import Foundation

// What first-run setup offers: activity templates to start from, and common distractions.
// Only suggestions; nothing here is applied until the user picks it.

struct ActivityTemplate: Hashable, Sendable {
    let name: String
    let icon: String       // SF Symbol
    let color: String      // one of ActivityStyle.colors
}

let activityTemplates: [ActivityTemplate] = [
    .init(name: "Work", icon: "briefcase.fill", color: "blue"),
    .init(name: "Study", icon: "graduationcap.fill", color: "indigo"),
    .init(name: "Coding", icon: "chevron.left.forwardslash.chevron.right", color: "purple"),
    .init(name: "Reading", icon: "book.fill", color: "brown"),
    .init(name: "Writing", icon: "pencil", color: "orange"),
    .init(name: "Languages", icon: "character.book.closed.fill", color: "green"),
    .init(name: "Side project", icon: "hammer.fill", color: "orange"),
    .init(name: "Design", icon: "paintbrush.fill", color: "pink"),
    .init(name: "Music practice", icon: "music.note", color: "mint"),
    .init(name: "Exercise", icon: "figure.run", color: "red"),
    .init(name: "Admin", icon: "tray.full.fill", color: "gray"),
    .init(name: "Rest", icon: "cup.and.saucer.fill", color: "brown"),
]

struct DistractionApp: Hashable, Sendable {
    let name: String
    let bundleIDs: [String]   // any one of them installed counts
    let suggested: Bool       // ticked by default; never for work tools or media players
}

let distractionApps: [DistractionApp] = [
    .init(name: "Telegram", bundleIDs: ["ru.keepcoder.Telegram", "com.tdesktop.telegram"], suggested: true),
    .init(name: "WhatsApp", bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], suggested: true),
    .init(name: "Discord", bundleIDs: ["com.hnc.Discord"], suggested: true),
    .init(name: "Viber", bundleIDs: ["com.viber.osx"], suggested: true),
    .init(name: "Steam", bundleIDs: ["com.valvesoftware.steam"], suggested: true),
    .init(name: "Messages", bundleIDs: ["com.apple.MobileSMS"], suggested: false),
    .init(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"], suggested: false),
    .init(name: "Music", bundleIDs: ["com.apple.Music"], suggested: false),
    .init(name: "Spotify", bundleIDs: ["com.spotify.client"], suggested: false),
    .init(name: "TV", bundleIDs: ["com.apple.TV"], suggested: false),
]

struct SiteGroup: Hashable, Sendable {
    let name: String
    let icon: String
    let sites: [String]
    let suggested: Bool
}

let siteGroups: [SiteGroup] = [
    .init(name: "Social", icon: "person.2.fill",
          sites: ["instagram.com", "facebook.com", "x.com", "twitter.com", "tiktok.com", "vk.com", "reddit.com"], suggested: true),
    .init(name: "Video", icon: "play.rectangle.fill",
          sites: ["youtube.com", "twitch.tv", "netflix.com", "rutube.ru", "vkvideo.ru"], suggested: true),
    .init(name: "News", icon: "newspaper.fill",
          sites: ["news.google.com", "lenta.ru", "ria.ru", "bbc.com", "cnn.com"], suggested: false),
    .init(name: "Shopping", icon: "cart.fill",
          sites: ["amazon.com", "ozon.ru", "wildberries.ru", "aliexpress.com", "ebay.com"], suggested: false),
]
