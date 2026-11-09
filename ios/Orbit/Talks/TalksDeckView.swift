// TalksDeckView.swift — Owner: Teammate C. PLACEHOLDER: replace with the swipe deck.
// Shows how to load data: APIClient.shared.recommendedTalks(pid:) returns [TalkCard].

import SwiftUI

struct TalksDeckView: View {
    @Environment(AppState.self) private var appState
    @State private var talks: [TalkCard] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(talks) { talk in
                VStack(alignment: .leading, spacing: 4) {
                    Text(talk.title).font(.headline)
                    Text("\(talk.room) · \(talk.start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let reason = talk.reason {
                        Text(reason).font(.footnote)
                    }
                }
            }
            .overlay {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            }
            .navigationTitle("Talks")
            .task {
                guard let pid = appState.profile?.pid else { return }
                do { talks = try await APIClient.shared.recommendedTalks(pid: pid) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
