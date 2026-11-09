// CalendarExporter.swift — writes saved talks and accepted meetups into the iPhone Calendar.
// Owner: Teammate C.
//
// Uses iOS 17's write-only access, which is the narrowest permission that does the job:
// Orbit can add events but can never read what else is in your calendar. That matters for
// the consent story — we ask for exactly what we need and nothing more.
//
// Write-only access means we cannot look up an event to see if it's already there, so we
// remember the event identifiers we created ourselves, keyed by talk id / meetup id.

import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class CalendarExporter {
    static let shared = CalendarExporter()

    enum Outcome: Equatable {
        case added(Int)
        case nothingNew
        case denied
        case failed(String)

        var message: String {
            switch self {
            case let .added(n): "Added \(n) event\(n == 1 ? "" : "s") to your calendar."
            case .nothingNew: "Everything is already in your calendar."
            case .denied: "Affinity needs calendar access. Open Settings › Affinity › Calendars to turn it on."
            case let .failed(detail): "Couldn't write to the calendar. \(detail)"
            }
        }

        var isError: Bool {
            switch self {
            case .denied, .failed: true
            case .added, .nothingNew: false
            }
        }
    }

    var lastOutcome: Outcome?
    var isWorking = false

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let idsKey = "orbit.calendar.eventIDs"

    private init() {}

    /// tid / meetup id  ->  EKEvent identifier we created.
    private var savedIDs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: idsKey) }
    }

    func isExported(_ key: String) -> Bool { savedIDs[key] != nil }

    var exportedCount: Int { savedIDs.count }

    /// Forget what we've written. Handy between demo runs.
    func resetExportHistory() {
        UserDefaults.standard.removeObject(forKey: idsKey)
    }

    // MARK: - Public entry points

    /// "Add all to Calendar" on MyCalendarView.
    @discardableResult
    func addTalks(_ items: [ScheduleItem]) async -> Outcome {
        await write(items.map {
            Draft(
                key: $0.tid,
                title: $0.title,
                location: $0.room,
                start: $0.start,
                end: $0.end,
                notes: $0.must ? "Must-attend · saved in Affinity" : "Saved in Affinity"
            )
        })
    }

    /// Called when a meetup is accepted, from either side.
    @discardableResult
    func addMeetup(_ meetup: Meetup, withName name: String?) async -> Outcome {
        let who = name ?? "your Affinity match"
        return await write([
            Draft(
                key: meetup.id,
                title: "Meet \(who)",
                location: meetup.place,
                start: meetup.start,
                end: meetup.end,
                notes: "Affinity meetup at \(meetup.place). Open Affinity and tap Find to walk over."
            )
        ])
    }

    // MARK: - Writing

    private struct Draft {
        let key: String
        let title: String
        let location: String
        let start: Date
        let end: Date
        let notes: String
    }

    private func write(_ drafts: [Draft]) async -> Outcome {
        isWorking = true
        defer { isWorking = false }

        guard await requestAccess() else {
            lastOutcome = .denied
            return .denied
        }

        let pending = drafts.filter { savedIDs[$0.key] == nil }
        guard !pending.isEmpty else {
            lastOutcome = .nothingNew
            return .nothingNew
        }

        guard let calendar = store.defaultCalendarForNewEvents else {
            let outcome = Outcome.failed("No default calendar is set on this iPhone.")
            lastOutcome = outcome
            return outcome
        }

        var ids = savedIDs
        var added = 0
        do {
            for draft in pending {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = draft.title
                event.location = draft.location
                event.startDate = draft.start
                event.endDate = draft.end
                event.notes = draft.notes
                event.timeZone = ConferenceTime.zone
                let alarm = EKAlarm(relativeOffset: -10 * 60)
                event.addAlarm(alarm)
                try store.save(event, span: .thisEvent, commit: false)
                if let id = event.eventIdentifier { ids[draft.key] = id }
                added += 1
            }
            try store.commit()
        } catch {
            store.reset()
            let outcome = Outcome.failed(error.localizedDescription)
            lastOutcome = outcome
            return outcome
        }

        savedIDs = ids
        let outcome = Outcome.added(added)
        lastOutcome = outcome
        return outcome
    }

    private func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        default:
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
    }
}
