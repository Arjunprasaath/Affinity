// MatchesListView.swift — everyone who swiped right on you after you swiped right on them.
// Owner: Teammate C.

import SwiftUI

struct MatchesListView: View {
    @Environment(AppState.self) private var appState

    @State private var matches: [Match] = []
    @State private var meetups: [Meetup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var pid: String? { appState.profile?.pid }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && matches.isEmpty {
                    ProgressView().frame(maxHeight: .infinity)
                } else if matches.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Matches")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() } }
            .refreshable { await load() }
            // Reload every time the Matches tab is opened, so new matches and meetups show up.
            .task(id: appState.selectedTab) {
                if appState.selectedTab == .matches { await load() }
            }
        }
    }

    private var list: some View {
        List {
            if !incoming.isEmpty {
                Section("Waiting on you") {
                    ForEach(incoming) { meetup in
                        NavigationLink(value: pidOfOther(in: meetup)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Meetup proposed", systemImage: "hand.raised.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text("\(meetup.place) · \(ConferenceTime.dayAndTime(meetup.start))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(matches.count == 1 ? "1 match" : "\(matches.count) matches") {
                ForEach(matches) { match in
                    NavigationLink(value: match.pid) {
                        MatchRow(match: match, meetup: nextMeetup(with: match.pid))
                    }
                }
            }

            Section {
                Text("Only shared talks and free time are visible. Live location never leaves your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationDestination(for: String.self) { otherPid in
            if let me = pid, let match = matches.first(where: { $0.pid == otherPid }) {
                MatchDetailView(me: me, match: match)
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No matches yet", systemImage: "heart.circle")
        } description: {
            Text("Swipe right on people. Mutual likes show up here.")
        } actions: {
            Button("Swipe people") { appState.selectedTab = .people }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Derived

    /// Proposals someone sent me that I haven't answered.
    private var incoming: [Meetup] {
        guard let pid else { return [] }
        return meetups.filter { $0.b == pid && $0.status == .proposed }
    }

    private func pidOfOther(in meetup: Meetup) -> String {
        guard let pid else { return meetup.b }
        return meetup.a == pid ? meetup.b : meetup.a
    }

    private func nextMeetup(with otherPid: String) -> Meetup? {
        meetups
            .filter { ($0.a == otherPid || $0.b == otherPid) && $0.status != .declined }
            .sorted { $0.start < $1.start }
            .first
    }

    private func load() async {
        guard let pid else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            matches = try await APIClient.shared.matches(pid: pid)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Meetups are a nice-to-have on this screen: never let them break the list.
        if let fetched = try? await APIClient.shared.meetups(pid: pid) {
            await MeetupBook.shared.record(fetched)
        }
        meetups = await MeetupBook.shared.all(for: pid)
    }
}

private struct MatchRow: View {
    let match: Match
    let meetup: Meetup?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: match.name, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(match.name).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if let meetup {
                    Label(
                        "\(meetup.status == .accepted ? "Meeting" : "Proposed") \(ConferenceTime.dayAndTime(meetup.start)) · \(meetup.place)",
                        systemImage: meetup.status == .accepted ? "checkmark.circle.fill" : "clock.badge.questionmark"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(meetup.status == .accepted ? .green : .orange)
                } else if let reason = match.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        let parts = [match.role, match.company].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
