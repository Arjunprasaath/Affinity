// ConferenceTime.swift — formatting helpers pinned to the conference's own time zone.
// Owner: Teammate C (shared by Talks, Calendar and Matches).
//
// Every date on the wire is an absolute instant with a -07:00 offset. If we formatted with
// the device time zone, a phone set to another region would show the wrong day and split
// "Nov 10" across two sections. So all display goes through here.

import Foundation

enum ConferenceTime {
    /// Salt Lake City. Change this one line if the event moves.
    static let zone = TimeZone(identifier: "America/Denver") ?? .current

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }()

    /// "3:30 PM"
    static func time(_ date: Date) -> String {
        formatter(dateStyle: .none, timeStyle: .short).string(from: date)
    }

    /// "3:30 – 4:10 PM"
    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "Tue, Nov 10"
    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return f.string(from: date)
    }

    /// "Tue 3:30 PM"
    static func dayAndTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f.string(from: date)
    }

    /// Minutes between two instants, rounded down. Used for timeline block heights.
    static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    /// "40 min" / "1 h 20 min"
    static func duration(_ start: Date, _ end: Date) -> String {
        let m = minutes(from: start, to: end)
        if m < 60 { return "\(m) min" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
    }

    /// Start of the conference day a date falls on, in conference time.
    static func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func formatter(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f
    }
}
