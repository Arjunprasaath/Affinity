// RadarView.swift — the Orbit radar. Owner: Jenish.
// Placeholder for the 3:00 hand-off; the real radar (rings, dots, glow, Find) replaces this next.

import SwiftUI

struct RadarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Orbit radar", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                if let pid = appState.radarFocusPid {
                    Text("Looking for \(pid). The live radar is coming next.")
                } else {
                    Text("People near you will show up here.")
                }
            }
            .navigationTitle("Orbit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() }
            }
        }
    }
}

#Preview {
    RadarView().environment(AppState())
}
