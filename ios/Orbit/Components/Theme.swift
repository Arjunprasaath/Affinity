// Theme.swift — Orbit's colours: one vivid accent, a brand gradient, and a stable colour per topic.

import SwiftUI

enum Theme {
    /// App-wide tint (buttons, selected tab, links).
    static let accent = Color(red: 0.45, green: 0.27, blue: 0.95)

    /// Violet → pink → orange, used for headers and the primary button.
    static let brand = LinearGradient(
        colors: [Color(red: 0.45, green: 0.27, blue: 0.95), .pink, .orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Soft background wash for full-screen pages.
    static let wash = LinearGradient(
        colors: [Color.purple.opacity(0.14), Color.pink.opacity(0.08), Color.orange.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let palette: [Color] = [.pink, .orange, .purple, .teal, .indigo, .mint, .blue, .green, .cyan]

    /// Same topic, same colour, everywhere in the app.
    static func color(for text: String) -> Color {
        let hash = text.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[(hash & Int.max) % palette.count]
    }
}
