// StubScheduleStore.swift — demo-mode memory of talk swipes. Owner: Jenish.
//
// With stub data on, there's no backend to remember what you swiped, so this does it in memory:
// right = saved, up = saved + must-attend, left = skipped. The Calendar tab is built from it,
// with clashes and free blocks computed the same way the backend does
// (free = gaps of 20+ minutes between 9:00 and 18:00, conference time).
// Resets when the app restarts.

import Foundation

final class StubScheduleStore {
    private let lock = NSLock()
    private var cards: [String: TalkCard] = [:]
    private var saved: [String: Bool] = [:]      // tid → must-attend
    private var skipped: Set<String> = []

    private static let conferenceCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? .current
        return calendar
    }()

    func remember(_ talks: [TalkCard]) {
        lock.withLock {
            for talk in talks { cards[talk.tid] = talk }
        }
    }

    /// Talks not yet swiped either way, so the deck doesn't repeat itself.
    func unswiped(_ talks: [TalkCard]) -> [TalkCard] {
        lock.withLock {
            talks.filter { saved[$0.tid] == nil && !skipped.contains($0.tid) }
        }
    }

    func record(_ swipe: Swipe) {
        lock.withLock {
            let tid = swipe.targetId
            switch swipe.dir {
            case .right:
                saved[tid] = false
                skipped.remove(tid)
            case .up:
                saved[tid] = true
                skipped.remove(tid)
            case .left:
                saved[tid] = nil
                skipped.insert(tid)
            }
        }
    }

    func schedule(pid: String) -> Schedule {
        lock.withLock {
            var items: [ScheduleItem] = saved.compactMap { tid, must in
                guard let card = cards[tid] else { return nil }
                return ScheduleItem(tid: card.tid, title: card.title, room: card.room,
                                    start: card.start, end: card.end, must: must, clash: false)
            }
            .sorted { $0.start < $1.start }

            // Clash = overlaps any other saved talk.
            for i in items.indices {
                items[i].clash = items.indices.contains { j in
                    j != i && items[i].start < items[j].end && items[j].start < items[i].end
                }
            }

            return Schedule(pid: pid, items: items, free: freeBlocks(around: items))
        }
    }

    private func freeBlocks(around items: [ScheduleItem]) -> [TimeBlock] {
        let calendar = Self.conferenceCalendar
        let minimumGap: TimeInterval = 20 * 60
        let days = Set(items.map { calendar.startOfDay(for: $0.start) }).sorted()
        var free: [TimeBlock] = []

        for day in days {
            guard let open = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { continue }
            var cursor = open
            for item in items where calendar.isDate(item.start, inSameDayAs: day) {
                if item.start.timeIntervalSince(cursor) >= minimumGap {
                    free.append(TimeBlock(start: cursor, end: item.start))
                }
                cursor = max(cursor, item.end)
            }
            if close.timeIntervalSince(cursor) >= minimumGap {
                free.append(TimeBlock(start: cursor, end: close))
            }
        }
        return free
    }
}
