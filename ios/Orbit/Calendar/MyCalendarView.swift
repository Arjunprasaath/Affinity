// MyCalendarView.swift — step 3: the conference you just built, as a day timeline.
// Owner: Teammate C.
//
// Saved talks are solid blocks, free time is dashed, clashes are red with a one-tap
// "keep this one" that left-swipes the loser for you. "Add all to Calendar" writes the
// day into the iPhone Calendar with EventKit.

import SwiftUI

struct MyCalendarView: View {
    @Environment(AppState.self) private var appState

    @State private var schedule: Schedule?
    @State private var selectedDay: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var banner: String?
    @State private var bannerIsError = false
    @State private var resolving: ClashGroup?

    private var exporter: CalendarExporter { .shared }
    private var pid: String? { appState.profile?.pid }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && schedule == nil {
                    ProgressView().frame(maxHeight: .infinity)
                } else if let schedule, !schedule.items.isEmpty {
                    timeline(for: schedule)
                } else {
                    emptyState
                }
            }
            .navigationTitle("My calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() }
            }
            .safeAreaInset(edge: .top) { if days.count > 1 { dayPicker } }
            .safeAreaInset(edge: .bottom) { if hasItemsToday { exportBar } }
            .overlay(alignment: .top) { bannerView }
            .refreshable { await load() }
            // Reload every time the Calendar tab is opened, so talks saved since then show up.
            .task(id: appState.selectedTab) {
                if appState.selectedTab == .calendar { await load() }
            }
            .sheet(item: $resolving) { group in
                ClashSheet(group: group) { keep in
                    Task { await resolve(group, keeping: keep) }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Day picker

    private var days: [Date] {
        let all = (schedule?.items.map { ConferenceTime.day(of: $0.start) } ?? [])
        return Array(Set(all)).sorted()
    }

    private var activeDay: Date? { selectedDay ?? days.first }

    private var dayPicker: some View {
        Picker("Day", selection: Binding(
            get: { activeDay ?? Date() },
            set: { selectedDay = $0 }
        )) {
            ForEach(days, id: \.self) { day in
                Text(ConferenceTime.dayLabel(day)).tag(day)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: - Timeline

    private func itemsToday(_ schedule: Schedule) -> [ScheduleItem] {
        guard let activeDay else { return schedule.items }
        return schedule.items
            .filter { ConferenceTime.day(of: $0.start) == activeDay }
            .sorted { $0.start < $1.start }
    }

    private func freeToday(_ schedule: Schedule) -> [TimeBlock] {
        guard let activeDay else { return schedule.free }
        return schedule.free
            .filter { ConferenceTime.day(of: $0.start) == activeDay }
            .sorted { $0.start < $1.start }
    }

    private var hasItemsToday: Bool {
        guard let schedule else { return false }
        return !itemsToday(schedule).isEmpty
    }

    private func timeline(for schedule: Schedule) -> some View {
        let items = itemsToday(schedule)
        let free = freeToday(schedule)
        let clashes = ClashGroup.groups(in: items)

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !clashes.isEmpty {
                    clashBanner(clashes)
                }

                ForEach(rows(items: items, free: free)) { row in
                    switch row.kind {
                    case let .talk(item):
                        TalkBlock(
                            item: item,
                            isExported: exporter.isExported(item.tid),
                            clashGroup: clashes.first { $0.contains(item) }
                        ) { group in
                            resolving = group
                        }
                    case let .free(block):
                        FreeBlock(block: block)
                    }
                }

                Text("Matches only see where your free time overlaps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private struct Row: Identifiable {
        enum Kind {
            case talk(ScheduleItem)
            case free(TimeBlock)
        }
        let id: String
        let kind: Kind
        let start: Date
    }

    private func rows(items: [ScheduleItem], free: [TimeBlock]) -> [Row] {
        let talkRows = items.map { Row(id: "t-\($0.tid)", kind: .talk($0), start: $0.start) }
        // Only gaps worth meeting in; the backend already filters to 20 minutes or more.
        let freeRows = free.map { Row(id: "f-\($0.id)", kind: .free($0), start: $0.start) }
        return (talkRows + freeRows).sorted { $0.start < $1.start }
    }

    private func clashBanner(_ clashes: [ClashGroup]) -> some View {
        Button {
            resolving = clashes.first
        } label: {
            Label(
                "\(clashes.count) clash\(clashes.count == 1 ? "" : "es") to sort out",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export

    private var exportBar: some View {
        let items = schedule.map { itemsToday($0) } ?? []
        let pending = items.filter { !exporter.isExported($0.tid) }
        return VStack(spacing: 0) {
            Divider()
            Button {
                Task {
                    let outcome = await exporter.addTalks(items)
                    show(outcome.message, isError: outcome.isError)
                }
            } label: {
                HStack {
                    if exporter.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: pending.isEmpty ? "checkmark.circle.fill" : "calendar.badge.plus")
                    }
                    Text(pending.isEmpty ? "In your iPhone Calendar" : "Add \(pending.count) to Calendar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pending.isEmpty || exporter.isWorking)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "calendar")
        } description: {
            Text("Swipe right on talks to fill your day.")
        } actions: {
            Button("Swipe talks") { appState.selectedTab = .talks }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
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

    // MARK: - Actions

    private func load() async {
        guard let pid else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await APIClient.shared.schedule(pid: pid)
            schedule = fresh
            if let activeDay, !days.contains(activeDay) { selectedDay = days.first }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            show(error.localizedDescription, isError: true)
        }
    }

    /// Keeping one side of a clash is just a left swipe on the other, so the backend's
    /// schedule (derived from swipes) stays the single source of truth.
    private func resolve(_ group: ClashGroup, keeping keep: ScheduleItem) async {
        resolving = nil
        guard let pid else { return }
        let drop = group.items.filter { $0.tid != keep.tid }
        for item in drop {
            _ = try? await APIClient.shared.swipe(
                Swipe(pid: pid, targetType: .talk, targetId: item.tid, dir: .left)
            )
        }
        await load()
        show("Kept \(keep.title).", isError: false)
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

// MARK: - Blocks

private struct TalkBlock: View {
    let item: ScheduleItem
    let isExported: Bool
    let clashGroup: ClashGroup?
    let onResolve: (ClashGroup) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ConferenceTime.time(item.start))
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(ConferenceTime.time(item.end))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(item.clash ? Color.red : (item.must ? Color.blue : Color.accentColor))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if item.must {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.blue)
                    }
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Label(item.room, systemImage: "mappin.and.ellipse")
                    Text(ConferenceTime.duration(item.start, item.end))
                    if isExported {
                        Label("In Calendar", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let clashGroup {
                    Button {
                        onResolve(clashGroup)
                    } label: {
                        Label("Overlaps another talk · fix", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(item.clash ? Color.red.opacity(0.5) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), \(ConferenceTime.range(item.start, item.end)), \(item.room)"
            + (item.must ? ", must attend" : "")
            + (item.clash ? ", clashes with another saved talk" : "")
            + (isExported ? ", already in your iPhone calendar" : "")
        )
    }
}

private struct FreeBlock: View {
    let block: TimeBlock

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(ConferenceTime.time(block.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Label(
                "Free · \(ConferenceTime.duration(block.start, block.end))",
                systemImage: "figure.stand.line.dotted.figure.stand"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.tertiary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Free from \(ConferenceTime.range(block.start, block.end))")
    }
}

// MARK: - Clashes

struct ClashGroup: Identifiable, Hashable {
    let items: [ScheduleItem]
    var id: String { items.map(\.tid).joined(separator: "+") }

    func contains(_ item: ScheduleItem) -> Bool { items.contains { $0.tid == item.tid } }

    /// Groups overlapping talks on the same day into one decision each.
    static func groups(in items: [ScheduleItem]) -> [ClashGroup] {
        let sorted = items.sorted { $0.start < $1.start }
        var groups: [[ScheduleItem]] = []
        for item in sorted {
            if let index = groups.indices.last,
               let last = groups[index].last,
               item.start < last.end {
                groups[index].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.filter { $0.count > 1 }.map { ClashGroup(items: $0) }
    }
}

private struct ClashSheet: View {
    let group: ClashGroup
    let onKeep: (ScheduleItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These overlap. Keep one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(group.items) { item in
                    Button {
                        onKeep(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text("\(ConferenceTime.range(item.start, item.end)) · \(item.room)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.must {
                                Label("You marked this must-attend", systemImage: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityHint("Keeps this talk and removes the other")
                }
            }
            .navigationTitle("Pick one")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
