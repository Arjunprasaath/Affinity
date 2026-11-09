// Theme.swift — Orbit's look: one calm indigo accent on plain system backgrounds.

import SwiftUI

enum Theme {
    /// App-wide tint (buttons, selected tab, links, chips).
    static let accent = Color.indigo

    /// Primary button fill and the wordmark. Solid, no gradient.
    static let brand = Color.indigo

    /// Page background: the standard grouped background, so it looks native in light and dark mode.
    static let wash = Color(.systemGroupedBackground)

    /// Topic chips use the single accent colour to keep things clean.
    static func color(for text: String) -> Color { accent }
}
