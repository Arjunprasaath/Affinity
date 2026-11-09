// PeopleDeckView.swift — Owner: Teammate C. PLACEHOLDER: replace with the people swipe deck.
// Data: APIClient.shared.recommendedPeople(pid:) returns [PersonCard].
// Swipe: APIClient.shared.swipe(Swipe(pid:targetType: .person, targetId:dir:)); result.match != nil means a mutual match.

import SwiftUI

struct PeopleDeckView: View {
    @Environment(AppState.self) private var appState
    @State private var people: [PersonCard] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(people) { person in
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).font(.headline)
                    Text([person.role, person.company].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(person.reason).font(.footnote)
                }
            }
            .overlay {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            }
            .navigationTitle("People")
            .task {
                guard let pid = appState.profile?.pid else { return }
                do { people = try await APIClient.shared.recommendedPeople(pid: pid) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
