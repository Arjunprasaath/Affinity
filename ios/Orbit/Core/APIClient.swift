// APIClient.swift — one async method per endpoint in the API contract (PLAN.md).
// Owner: Jenish. Teammates call these; ask before changing signatures.
//
// With stubs on (the default), every call returns the bundled JSON in Core/Stubs,
// so screens can be built before the backend is live. Flip it off in Developer settings.

import Foundation

enum APIError: LocalizedError {
    case badStatus(Int, String)
    case missingStub(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .badStatus(code, body): "The server returned \(code). \(body.prefix(200))"
        case let .missingStub(name): "Missing stub file \(name).json."
        case let .invalidURL(path): "Couldn't build a URL for \(path)."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// Stub mode only: remembers talk swipes so the Calendar tab shows what you actually saved.
    private let stubSchedule = StubScheduleStore()

    init(session: URLSession = .shared) {
        self.session = session
    }

    var baseURL: URL { AppConfig.apiBaseURL }
    var useStubs: Bool { AppConfig.useStubs }

    // MARK: - Profiles

    func createProfile(_ new: NewProfile) async throws -> Profile {
        if useStubs {
            var profile: Profile = try Self.stub("stub_profile")
            profile.pid = Self.randomPid()   // unique per phone, so two stub-mode phones can see each other
            profile.name = new.name
            profile.role = new.role
            profile.company = new.company
            profile.pronouns = new.pronouns
            profile.github = new.github
            profile.workingOn = new.workingOn
            profile.lookingFor = new.lookingFor
            profile.offering = new.offering
            profile.hereFor = new.hereFor
            profile.status = new.status
            return profile
        }
        return try await request("POST", "profiles", body: new)
    }

    func profile(pid: String) async throws -> Profile {
        if useStubs {
            let personas: [Profile] = try Self.stub("stub_personas")
            if let persona = personas.first(where: { $0.pid == pid }) { return persona }
            var mine: Profile = try Self.stub("stub_profile")
            mine.pid = pid
            return mine
        }
        return try await get("profiles/\(pid)", stub: "stub_profile")
    }

    func updateProfile(pid: String, _ patch: ProfilePatch) async throws -> Profile {
        if useStubs {
            var profile: Profile = try Self.stub("stub_profile")
            if let topics = patch.topics { profile.topics = topics }
            if let status = patch.status { profile.status = status }
            if let hide = patch.hideNextRoom { profile.hideNextRoom = hide }
            return profile
        }
        return try await request("PATCH", "profiles/\(pid)", body: patch)
    }

    // MARK: - Talks and schedule

    func recommendedTalks(pid: String, limit: Int = 10) async throws -> [TalkCard] {
        if useStubs {
            let all: [TalkCard] = try Self.stub("stub_talks_recommended")
            stubSchedule.remember(all)
            return Array(stubSchedule.unswiped(all).prefix(limit))
        }
        return try await get("talks/recommended", query: ["pid": pid, "limit": String(limit)], stub: "stub_talks_recommended")
    }

    func swipe(_ swipe: Swipe) async throws -> SwipeResult {
        if useStubs {
            if swipe.targetType == .talk {
                stubSchedule.record(swipe)
                return SwipeResult(ok: true, match: nil)
            }
            // In stub mode, every right swipe on a person is a match so the match flow can be built.
            if swipe.targetType == .person && swipe.dir == .right {
                return try Self.stub("stub_swipe_match")
            }
            return SwipeResult(ok: true, match: nil)
        }
        return try await request("POST", "swipes", body: swipe)
    }

    func schedule(pid: String) async throws -> Schedule {
        if useStubs { return stubSchedule.schedule(pid: pid) }
        return try await get("schedule/\(pid)", stub: "stub_schedule")
    }

    // MARK: - People and matches

    func recommendedPeople(pid: String, limit: Int = 10) async throws -> [PersonCard] {
        try await get("people/recommended", query: ["pid": pid, "limit": String(limit)], stub: "stub_people_recommended")
    }

    func matches(pid: String) async throws -> [Match] {
        try await get("matches/\(pid)", stub: "stub_matches")
    }

    func meet(a: String, b: String) async throws -> MeetView {
        try await get("meet", query: ["a": a, "b": b], stub: "stub_meet")
    }

    func proposeMeetup(_ meetup: NewMeetup) async throws -> Meetup {
        if useStubs {
            var stub: Meetup = try Self.stub("stub_meetup")
            stub.a = meetup.a
            stub.b = meetup.b
            stub.place = meetup.place
            stub.start = meetup.start
            stub.end = meetup.end
            stub.status = .proposed
            return stub
        }
        return try await request("POST", "meetups", body: meetup)
    }

    func updateMeetup(id: String, status: MeetupStatus) async throws -> Meetup {
        if useStubs {
            var stub: Meetup = try Self.stub("stub_meetup")
            stub.id = id
            stub.status = status
            return stub
        }
        return try await request("PATCH", "meetups/\(id)", body: MeetupUpdate(status: status))
    }

    // MARK: - Radar

    /// Glow tier for each nearby pid. Unknown pids come back as `.weak`.
    func radarMatch(me: String, others: [String]) async throws -> [RadarResult] {
        guard !others.isEmpty else { return [] }
        if useStubs {
            let all: [RadarResult] = try Self.stub("stub_radar_match")
            // Real phones in stub mode get "strong" so the glow can be tested between two iPhones.
            return others.map { pid in
                all.first { $0.pid == pid } ?? RadarResult(pid: pid, tier: .strong, reason: "Another Affinity user nearby (stub data)")
            }
        }
        return try await request("POST", "radar/match", body: RadarMatchRequest(me: me, others: others))
    }

    func health() async throws -> Health {
        if useStubs { return Health(ok: true) }
        return try await request("GET", "healthz", body: Optional<NoBody>.none)
    }

    // MARK: - Stubs

    static func randomPid() -> String {
        "p_" + UUID().uuidString.prefix(8).lowercased()
    }

    /// Loads `name.json` from the app bundle. Also handy in SwiftUI previews.
    static func stub<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw APIError.missingStub(name)
        }
        return try OrbitJSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: - Plumbing

    private struct NoBody: Encodable {}

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], stub: String) async throws -> T {
        if useStubs { return try Self.stub(stub) }
        return try await request("GET", path, query: query, body: Optional<NoBody>.none)
    }

    private func request<T: Decodable, Body: Encodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Body?
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(path)
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try OrbitJSON.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.badStatus(status, String(decoding: data, as: UTF8.self))
        }
        return try OrbitJSON.decoder.decode(T.self, from: data)
    }
}
