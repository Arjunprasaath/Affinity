// Models.swift — Codable types for the Orbit API contract (see PLAN.md → "API contract").
// Owner: Jenish. Teammates: please don't edit; ask for changes so the app and backend stay in sync.
//
// JSON keys are snake_case on the wire and camelCase here (OrbitJSON converts automatically).
// Dates are ISO-8601 strings, with or without fractional seconds.

import Foundation

// MARK: - Shared enums

enum PresenceStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case green, yellow, red

    var id: String { rawValue }

    var label: String {
        switch self {
        case .green: "Open to chat"
        case .yellow: "Ask first"
        case .red: "Invisible"
        }
    }
}

/// UI helper for the "Here for" chips. The wire format stays `[String]` so unknown values never break decoding.
enum HereFor: String, CaseIterable, Identifiable, Hashable {
    case hiring
    case jobHunting = "job_hunting"
    case learning
    case findingContributors = "finding_contributors"
    case meetingUsers = "meeting_users"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hiring: "Hiring"
        case .jobHunting: "Job hunting"
        case .learning: "Learning"
        case .findingContributors: "Finding contributors"
        case .meetingUsers: "Meeting users"
        }
    }
}

struct TimeBlock: Codable, Hashable, Identifiable {
    var start: Date
    var end: Date

    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
}

// MARK: - Profiles

struct Profile: Codable, Hashable, Identifiable {
    var pid: String
    var name: String
    var role: String?
    var company: String?
    var pronouns: String?
    var github: String?
    var workingOn: String?
    var lookingFor: String?
    var offering: String?
    var hereFor: [String]
    var topics: [String]
    var summary: String?
    var status: PresenceStatus
    var hideNextRoom: Bool?

    var id: String { pid }
}

/// Body for `POST /profiles`. Empty optional fields are sent as missing, not "".
struct NewProfile: Encodable, Hashable {
    var name: String
    var role: String?
    var company: String?
    var pronouns: String?
    var github: String?
    var workingOn: String?
    var lookingFor: String?
    var offering: String?
    var hereFor: [String]
    var status: PresenceStatus
}

/// Body for `PATCH /profiles/:pid`. Only non-nil fields are sent.
struct ProfilePatch: Encodable, Hashable {
    var topics: [String]? = nil
    var status: PresenceStatus? = nil
    var hideNextRoom: Bool? = nil
}

// MARK: - Talks and schedule

struct TalkCard: Codable, Hashable, Identifiable {
    var tid: String
    var title: String
    var abstract: String?
    var speakers: [String]
    var room: String
    var start: Date
    var end: Date
    var level: String?
    var track: String?
    var topics: [String]?
    var reason: String?
    /// The must-attend talk this one overlaps with, if any.
    var clashesWith: ClashRef?

    var id: String { tid }
}

struct ClashRef: Codable, Hashable {
    var tid: String
    var title: String
}

struct ScheduleItem: Codable, Hashable, Identifiable {
    var tid: String
    var title: String
    var room: String
    var start: Date
    var end: Date
    var must: Bool
    var clash: Bool

    var id: String { tid }
}

struct Schedule: Codable, Hashable {
    var pid: String
    var items: [ScheduleItem]
    var free: [TimeBlock]
}

// MARK: - Swipes

enum SwipeTarget: String, Codable, Hashable { case talk, person }
enum SwipeDirection: String, Codable, Hashable { case right, up, left }

/// Body for `POST /swipes`.
struct Swipe: Encodable, Hashable {
    var pid: String
    var targetType: SwipeTarget
    var targetId: String
    var dir: SwipeDirection
}

struct SwipeResult: Codable, Hashable {
    var ok: Bool
    /// Present when a person swipe completed a mutual match.
    var match: Match?
}

// MARK: - People and matches

struct PersonCard: Codable, Hashable, Identifiable {
    var pid: String
    var name: String
    var role: String?
    var company: String?
    var pronouns: String?
    var github: String?
    var status: PresenceStatus?
    var topics: [String]?
    var workingOn: String?
    var hereFor: [String]
    var sharedTopics: [String]
    var sharedTalksCount: Int
    var score: Double
    var reason: String

    var id: String { pid }
}

struct Match: Codable, Hashable, Identifiable {
    var pid: String
    var name: String
    var role: String?
    var company: String?
    var matchedAt: Date?
    var reason: String?

    var id: String { pid }
}

// MARK: - Meet (partial calendar reveal)

struct SharedTalk: Codable, Hashable, Identifiable {
    var tid: String
    var title: String
    var room: String
    var start: Date
    var end: Date

    var id: String { tid }
}

struct NextRoom: Codable, Hashable {
    var room: String
    var from: Date?
    var until: Date
    var planned: Bool
}

struct MeetSuggestion: Codable, Hashable, Identifiable {
    /// "after_shared_talk" or "free_overlap".
    var kind: String
    var place: String
    var start: Date
    var end: Date
    var label: String

    var id: String { "\(kind)-\(start.timeIntervalSince1970)-\(place)" }
}

struct MeetView: Codable, Hashable {
    /// The other person's pid.
    var with: String
    /// The other person's name.
    var name: String?
    var sharedTalks: [SharedTalk]
    var freeOverlaps: [TimeBlock]
    /// Missing when the other person turned on "Hide where I'll be".
    var theirNext: NextRoom?
    var suggestions: [MeetSuggestion]
}

enum MeetupStatus: String, Codable, Hashable { case proposed, accepted, declined }

struct Meetup: Codable, Hashable, Identifiable {
    var id: String
    var a: String
    var b: String
    var place: String
    var start: Date
    var end: Date
    var status: MeetupStatus
}

/// Body for `POST /meetups`.
struct NewMeetup: Encodable, Hashable {
    var a: String
    var b: String
    var start: Date
    var end: Date
    var place: String
}

/// Body for `PATCH /meetups/:id`.
struct MeetupUpdate: Encodable, Hashable {
    var status: MeetupStatus
}

// MARK: - Radar

enum RadarTier: String, Codable, Hashable, Comparable {
    case match, strong, good, weak

    private var rank: Int {
        switch self {
        case .match: 0
        case .strong: 1
        case .good: 2
        case .weak: 3
        }
    }

    static func < (lhs: RadarTier, rhs: RadarTier) -> Bool { lhs.rank < rhs.rank }
}

/// Body for `POST /radar/match`.
struct RadarMatchRequest: Encodable, Hashable {
    var me: String
    var others: [String]
}

struct RadarResult: Codable, Hashable, Identifiable {
    var pid: String
    var name: String? = nil
    var tier: RadarTier
    var score: Double? = nil
    var reason: String?

    var id: String { pid }
}

struct Health: Codable, Hashable {
    var ok: Bool
}

// MARK: - JSON coding

enum OrbitJSON {
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Decodes snake_case keys and ISO-8601 dates (Node's `toISOString()` adds milliseconds, so accept both).
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoPlain.date(from: string) ?? isoFractional.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoPlain.string(from: date))
        }
        return e
    }()
}
