// MatchDetailView.swift — step 5: the partial calendar reveal, and where you can meet.
// Owner: Teammate C.
//
// This screen is the consent model made visible. It shows, and can only show:
//   · the talks you BOTH saved
//   · the times you're BOTH free (the intersection, not either person's day)
//   · where they'll be next, planned, and only if they haven't hidden it
// Never their full schedule, and never a live position. GET /meet enforces the same thing
// server-side: it returns 403 unless the two of you are a mutual match.

import SwiftUI

struct MatchDetailView: View {
    let me: String
    let match: Match

    @Environment(AppState.self) private var appState

    @State private var meet: MeetView?
    @State private var meetups: [Meetup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busySuggestion: MeetSuggestion.ID?
    @State private var busyMeetup: String?
    @State private var banner: String?
    @State private var bannerIsError = false

    private var firstName: String {
        match.name.split(separator: " ").first.map(String.init) ?? match.name
    }

    var body: some View {
        List {
            if isLoading && meet == nil {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !pendingForMe.isEmpty { incomingSection }
            if !agreed.isEmpty { agreedSection }

            if let meet {
                sharedTalksSection(meet)
                freeSection(meet)
                if let next = meet.theirNext { nextRoomSection(next) }
                if !meet.suggestions.isEmpty { suggestionsSection(meet) }
            }

            privacySection
        }
        .navigationTitle(match.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.findOnRadar(pid: match.pid)
                } label: {
                    Label("Find on radar", systemImage: "dot.radiowaves.left.and.right")
                }
                .accessibilityLabel("Find \(firstName) on the Orbit radar")
            }
        }
        .overlay(alignment: .top) { bannerView }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Sections

    private func sharedTalksSection(_ meet: MeetView) -> some View {
        Section {
            if meet.sharedTalks.isEmpty {
                Text("No shared talks yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meet.sharedTalks) { talk in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(talk.title).font(.subheadline.weight(.semibold))
                        Text("\(ConferenceTime.dayAndTime(talk.start)) – \(ConferenceTime.time(talk.end)) · \(talk.room)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Label("Talks you're both going to", systemImage: "rectangle.stack.badge.checkmark")
        }
    }

    private func freeSection(_ meet: MeetView) -> some View {
        Section {
            if meet.freeOverlaps.isEmpty {
                Text("No shared free time yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meet.freeOverlaps) { block in
                    HStack {
                        Text(ConferenceTime.dayLabel(block.start)).foregroundStyle(.secondary)
                        Spacer()
                        Text(ConferenceTime.range(block.start, block.end))
                            .font(.callout.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Both free \(ConferenceTime.dayLabel(block.start)), \(ConferenceTime.range(block.start, block.end))")
                }
            }
        } header: {
            Label("Times you're both free", systemImage: "clock.arrow.2.circlepath")
        } footer: {
            Text("Only the overlap is shared.")
        }
    }

    private func nextRoomSection(_ next: NextRoom) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(next.room).font(.subheadline.weight(.semibold))
                Text("Until \(ConferenceTime.time(next.until))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Planned, from their saved talks — not a live location", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Label("Where \(firstName) will be next", systemImage: "mappin.and.ellipse")
        }
    }

    private func suggestionsSection(_ meet: MeetView) -> some View {
        Section {
            ForEach(meet.suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: suggestion.kind == "after_shared_talk" ? "door.left.hand.open" : "cup.and.saucer.fill")
                            .foregroundStyle(.tint)
                        Text(suggestion.label).font(.subheadline.weight(.semibold))
                    }
                    Text("\(suggestion.place) · \(ConferenceTime.dayAndTime(suggestion.start)) – \(ConferenceTime.time(suggestion.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let existing = meetup(matching: suggestion) {
                        Label(
                            existing.status == .accepted ? "Agreed" : "Proposed, waiting on \(firstName)",
                            systemImage: existing.status == .accepted ? "checkmark.circle.fill" : "paperplane"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(existing.status == .accepted ? .green : .orange)
                    } else {
                        Button {
                            Task { await propose(suggestion) }
                        } label: {
                            if busySuggestion == suggestion.id {
                                ProgressView()
                            } else {
                                Label("Propose", systemImage: "paperplane.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(busySuggestion != nil)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("Where you can meet", systemImage: "sparkles")
        } footer: {
            Text("Accepted meetups go in both calendars.")
        }
    }

    private var incomingSection: some View {
        Section {
            ForEach(pendingForMe) { meetup in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(firstName) suggested meeting")
                        .font(.subheadline.weight(.semibold))
                    Text("\(meetup.place) · \(ConferenceTime.dayAndTime(meetup.start)) – \(ConferenceTime.time(meetup.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            Task { await respond(meetup, .accepted) }
                        } label: {
                            if busyMeetup == meetup.id {
                                ProgressView()
                            } else {
                                Label("Accept", systemImage: "checkmark")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            Task { await respond(meetup, .declined) }
                        } label: {
                            Label("Decline", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.secondary)
                    }
                    .disabled(busyMeetup != nil)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("Waiting on you", systemImage: "hand.raised.fill")
        }
    }

    private var agreedSection: some View {
        Section {
            ForEach(agreed) { meetup in
                VStack(alignment: .leading, spacing: 6) {
                    Label(meetup.place, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("\(ConferenceTime.dayAndTime(meetup.start)) – \(ConferenceTime.time(meetup.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if CalendarExporter.shared.isExported(meetup.id) {
                            Label("In your Calendar", systemImage: "calendar.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button("Add to Calendar") {
                                Task {
                                    let outcome = await CalendarExporter.shared.addMeetup(meetup, withName: match.name)
                                    show(outcome.message, isError: outcome.isError)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        Button("Find on radar") { appState.findOnRadar(pid: match.pid) }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("You're meeting", systemImage: "person.2.fill")
        }
    }

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(firstName) sees exactly what you see here, and nothing more", systemImage: "lock.shield")
                Label("Live distance is measured phone to phone and never sent to the server", systemImage: "antenna.radiowaves.left.and.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Text(banner)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bannerIsError ? Color.red.opacity(0.92) : Color.green.opacity(0.92), in: Capsule())
                .foregroundStyle(.white)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Derived

    private var pendingForMe: [Meetup] {
        meetups.filter { $0.status == .proposed && $0.b == me }
    }

    private var agreed: [Meetup] {
        meetups.filter { $0.status == .accepted }
    }

    /// A suggestion already proposed: same place and start, either direction.
    private func meetup(matching suggestion: MeetSuggestion) -> Meetup? {
        meetups.first {
            $0.status != .declined
            && $0.place == suggestion.place
            && abs($0.start.timeIntervalSince(suggestion.start)) < 60
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meet = try await APIClient.shared.meet(a: me, b: match.pid)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        if let fetched = try? await APIClient.shared.meetups(pid: me) {
            await MeetupBook.shared.record(fetched)
        }
        meetups = await MeetupBook.shared.between(me, match.pid)
    }

    private func propose(_ suggestion: MeetSuggestion) async {
        busySuggestion = suggestion.id
        defer { busySuggestion = nil }
        do {
            let created = try await APIClient.shared.proposeMeetup(
                NewMeetup(a: me, b: match.pid, start: suggestion.start, end: suggestion.end, place: suggestion.place)
            )
            await MeetupBook.shared.record(created)
            meetups = await MeetupBook.shared.between(me, match.pid)
            show("Sent to \(firstName).", isError: false)
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func respond(_ meetup: Meetup, _ status: MeetupStatus) async {
        busyMeetup = meetup.id
        defer { busyMeetup = nil }
        do {
            let updated = try await APIClient.shared.respondToMeetup(id: meetup.id, status: status, as: me)
            await MeetupBook.shared.record(updated)
            meetups = await MeetupBook.shared.between(me, match.pid)
            if status == .accepted {
                let outcome = await CalendarExporter.shared.addMeetup(updated, withName: match.name)
                show(outcome.isError ? outcome.message : "Accepted. \(outcome.message)", isError: outcome.isError)
            } else {
                show("Declined.", isError: false)
            }
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ message: String, isError: Bool) {
        bannerIsError = isError
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { banner = nil }
        }
    }
}
