// MatchesListView.swift — Owner: Teammate C. PLACEHOLDER: replace with MatchesList + MatchDetailView.
// Data: APIClient.shared.matches(pid:) and APIClient.shared.meet(a:b:) (shared talks, free overlaps, suggestions).
// "Find on radar": call appState.findOnRadar(pid:) and the app switches to the Orbit tab.

import SwiftUI

struct MatchesListView: View {
    @Environment(AppState.self) private var appState
    @State private var matches: [Match] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(matches) { match in
                VStack(alignment: .leading, spacing: 6) {
                    Text(match.name).font(.headline)
                    if let reason = match.reason { Text(reason).font(.footnote) }
                    Button("Find on radar") { appState.findOnRadar(pid: match.pid) }
                        .buttonStyle(.bordered)
                }
            }
            .overlay {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            }
            .navigationTitle("Matches")
            .task {
                guard let pid = appState.profile?.pid else { return }
                do { matches = try await APIClient.shared.matches(pid: pid) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
