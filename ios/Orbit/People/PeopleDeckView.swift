// PeopleDeckView.swift — step 4: swipe people. A match needs both sides to swipe right.
// Owner: Teammate C.
//
// POST /swipes returns the match when the other person had already swiped right on you,
// which is the on-stage moment: swipe right on a persona, "You're connected" appears, and the
// partial calendar reveal unlocks.

import SwiftUI

struct PeopleDeckView: View {
    @Environment(AppState.self) private var appState

    @State private var deck: [PersonCard] = []
    @State private var isLoading = false
    @State private var isRefilling = false
    @State private var exhausted = false
    @State private var errorMessage: String?
    @State private var newMatch: Match?
    @State private var matchCount = 0

    private var pid: String? { appState.profile?.pid }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && deck.isEmpty {
                    ProgressView("Finding people worth meeting…").frame(maxHeight: .infinity)
                } else if deck.isEmpty {
                    emptyState
                } else {
                    SwipeDeck(items: deck, labels: .people, onSwipe: handle) { person in
                        PersonCardView(person: person)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
            .safeAreaInset(edge: .top) { header }
            .navigationTitle("People")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() } }
            .alert("Couldn't load people", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Retry") { Task { await load(reset: true) } }
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $newMatch) { match in
                MatchCelebrationView(match: match) {
                    newMatch = nil
                    appState.selectedTab = .matches
                }
                .presentationDetents([.medium])
            }
            .task {
                if deck.isEmpty && !exhausted { await load(reset: true) }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("A match takes both of you")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if matchCount > 0 {
                Button("\(matchCount) match\(matchCount == 1 ? "" : "es")") { appState.selectedTab = .matches }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("You've seen everyone for now", systemImage: "person.2")
        } description: {
            Text("Save more talks for better matches.")
        } actions: {
            if matchCount > 0 {
                Button("See my matches") { appState.selectedTab = .matches }
                    .buttonStyle(.borderedProminent)
            }
            Button("Swipe more talks") { appState.selectedTab = .talks }
            Button("Refresh") { Task { await load(reset: true) } }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handle(_ person: PersonCard, _ direction: SwipeDirection) {
        deck.removeAll { $0.pid == person.pid }
        guard let pid else { return }
        // Up isn't offered on this deck, but treat it as a right swipe if it ever arrives.
        let dir: SwipeDirection = direction == .up ? .right : direction
        Task {
            let result = try? await APIClient.shared.swipe(
                Swipe(pid: pid, targetType: .person, targetId: person.pid, dir: dir)
            )
            if let match = result?.match {
                matchCount += 1
                newMatch = match
            }
            if deck.count <= 2 { await load(reset: false) }
        }
    }

    private func load(reset: Bool) async {
        guard let pid else { return }
        if reset {
            isLoading = true
            exhausted = false
        } else {
            guard !isRefilling, !exhausted else { return }
            isRefilling = true
        }
        defer {
            isLoading = false
            isRefilling = false
        }

        do {
            let page = try await APIClient.shared.recommendedPeople(pid: pid, limit: 10)
            let known = Set(deck.map(\.pid))
            let fresh = page.filter { !known.contains($0.pid) }
            if reset {
                deck = page
            } else {
                deck.append(contentsOf: fresh)
                if fresh.isEmpty { exhausted = true }
            }
            if page.isEmpty { exhausted = true }
            errorMessage = nil
        } catch {
            if reset { errorMessage = error.localizedDescription }
        }
    }
}

/// The "it's a match" moment. Short, loud, and one tap away from the reveal.
struct MatchCelebrationView: View {
    let match: Match
    let onOpen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 124, height: 124)
                Avatar(name: match.name, size: 84)
            }
            .padding(.top, 28)

            Text("You're connected")
                .font(.title.bold())

            Text("You and \(match.name.split(separator: " ").first.map(String.init) ?? match.name) both want to meet.")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let reason = match.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Label("You can now see the talks you both saved and when you're both free", systemImage: "lock.open.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onOpen) {
                    Text("See where we can meet")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button("Keep swiping") { dismiss() }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .multilineTextAlignment(.center)
        .onAppear { pulse = true }
        .accessibilityElement(children: .contain)
    }
}
