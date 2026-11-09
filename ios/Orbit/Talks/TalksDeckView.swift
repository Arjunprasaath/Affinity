// TalksDeckView.swift — step 2 of the journey: swipe talks into your conference.
// Owner: Teammate C.
//
// Right = save · Up = must-attend · Left = skip. Each decision is POSTed to /swipes
// straight away, so the deck's next page already reflects what you liked (the backend
// feeds right-swiped titles back into the query).

import SwiftUI

struct TalksDeckView: View {
    @Environment(AppState.self) private var appState

    @State private var deck: [TalkCard] = []
    @State private var savedCount = 0
    @State private var mustCount = 0
    @State private var isLoading = false
    @State private var isRefilling = false
    @State private var errorMessage: String?
    @State private var lastSaved: TalkCard?
    @State private var exhausted = false

    private var pid: String? { appState.profile?.pid }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && deck.isEmpty {
                    ProgressView("Finding talks for you…")
                        .frame(maxHeight: .infinity)
                } else if deck.isEmpty {
                    emptyState
                } else {
                    SwipeDeck(items: deck, labels: .talks, onSwipe: handle) { talk in
                        TalkCardView(talk: talk)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
            .safeAreaInset(edge: .top) { counters }
            .navigationTitle("Talks")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() } }
            .alert("Couldn't load talks", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Retry") { Task { await load(reset: true) } }
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                if deck.isEmpty && !exhausted { await load(reset: true) }
            }
        }
    }

    // MARK: - Pieces

    private var counters: some View {
        HStack(spacing: 10) {
            Chip(text: "\(savedCount) saved", tint: .green)
            if mustCount > 0 { Chip(text: "\(mustCount) must-attend", tint: .blue) }
            Spacer()
            if savedCount > 0 {
                Button("See calendar") { appState.selectedTab = .calendar }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(savedCount > 0 ? "That's your conference" : "No talks to show", systemImage: "rectangle.stack.badge.person.crop")
        } description: {
            if savedCount > 0 {
                Text("\(savedCount) saved. Now find your people.")
            } else {
                Text("No talks found. Pull to retry.")
            }
        } actions: {
            if savedCount > 0 {
                Button("Open my calendar") { appState.selectedTab = .calendar }
                    .buttonStyle(.borderedProminent)
                Button("Swipe people") { appState.selectedTab = .people }
            } else {
                Button("Try again") { Task { await load(reset: true) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handle(_ talk: TalkCard, _ direction: SwipeDirection) {
        deck.removeAll { $0.tid == talk.tid }
        switch direction {
        case .right: savedCount += 1; lastSaved = talk
        case .up: savedCount += 1; mustCount += 1; lastSaved = talk
        case .left: break
        }

        guard let pid else { return }
        Task {
            // Fire and forget: a failed swipe must never block the deck during the demo.
            _ = try? await APIClient.shared.swipe(
                Swipe(pid: pid, targetType: .talk, targetId: talk.tid, dir: direction)
            )
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
            let page = try await APIClient.shared.recommendedTalks(pid: pid, limit: 10)
            let known = Set(deck.map(\.tid))
            let fresh = page.filter { !known.contains($0.tid) }
            if reset {
                deck = page
            } else {
                deck.append(contentsOf: fresh)
            }
            // The backend excludes talks you already swiped, so an empty page means the deck is done.
            if fresh.isEmpty && !reset { exhausted = true }
            if page.isEmpty { exhausted = true }
            errorMessage = nil
        } catch {
            if reset { errorMessage = error.localizedDescription }
        }
    }
}
