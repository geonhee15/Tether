import Foundation

/// Static facts about the app shown on the login screen, the footer and Settings › About.
enum AppInfo {
    static let name = "Tether"
    static let developer = "Geonhee Kim"
    static let developerURL = URL(string: "https://github.com/geonhee15")!
    static let repositoryURL = URL(string: "https://github.com/geonhee15/Tether")!
    static let maxAccounts = 10

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "-"
    }

    /// AI collaborators, in the order they joined. Append a new entry whenever the model changes.
    static let aiCredits = ["Claude Fable 5.2 High"]

    static var aiCreditLine: String { "With " + aiCredits.joined(separator: " / ") }

    /// (what, detail) pairs for the "Built with" list.
    static let stack: [(String, String)] = [
        ("Swift 6.2", "Swift 5 language mode · swiftc, no Xcode project"),
        ("SwiftUI", "Interface, animation, Observation"),
        ("AppKit · TextKit", "Window chrome and the rich text editor"),
        ("Swift Charts", "Pie, bar and line charts"),
        ("CryptoKit", "Salted password hashing"),
        ("Liquid Glass", "macOS 26 glass, material fallback on macOS 14–15"),
    ]

    static let designNotes: [(String, String)] = [
        ("ATFM glass theme", "Card, chip and tint system carried over and extended"),
        ("Claude Code · dataviz skill", "Colour-blind-safe chart palette for light and dark"),
    ]
}
