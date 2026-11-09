// MeetupsAPI.swift — the two meetup calls the shared APIClient doesn't cover yet.
// Owner: Teammate C.
//
// The backend has `GET /meetups?pid=` (every meetup you're in, proposed or decided) and
// expects `PATCH /meetups/:id` to carry `{status, pid}`, because only the invited person
// may accept or decline. Core/APIClient.swift belongs to Jenish, so rather than editing it
// mid-hackathon these two live here as an extension and use the same config and JSON coding.
//
// Jenish: if you'd rather fold these into APIClient, the signatures are
//   meetups(pid:) -> [Meetup]   and   respondToMeetup(id:status:as:) -> Meetup
// and deleting this file is then safe.

import Foundation

extension APIClient {
    /// Every meetup this person is part of, earliest first. In stub mode this is whatever
    /// the local book has (so propose → accept still works with the backend switched off).
    func meetups(pid: String) async throws -> [Meetup] {
        if useStubs { return await MeetupBook.shared.all(for: pid) }
        var components = URLComponents(url: baseURL.appending(path: "meetups"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "pid", value: pid)]
        guard let url = components?.url else { throw APIError.invalidURL("meetups") }
        return try await send(URLRequest(url: url))
    }

    /// Accept or decline. `pid` must be the invited side; the backend returns 403 otherwise.
    func respondToMeetup(id: String, status: MeetupStatus, as pid: String) async throws -> Meetup {
        if useStubs {
            guard var meetup = await MeetupBook.shared.find(id) else {
                throw APIError.badStatus(404, "No such meetup in stub mode.")
            }
            meetup.status = status
            await MeetupBook.shared.record(meetup)
            return meetup
        }
        var request = URLRequest(url: baseURL.appending(path: "meetups/\(id)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try OrbitJSON.encoder.encode(MeetupDecision(status: status, pid: pid))
        return try await send(request)
    }

    private func send<T: Decodable>(_ base: URLRequest) async throws -> T {
        var request = base
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.badStatus(status, String(decoding: data, as: UTF8.self))
        }
        return try OrbitJSON.decoder.decode(T.self, from: data)
    }
}

private struct MeetupDecision: Encodable {
    var status: MeetupStatus
    var pid: String
}

/// Meetups we know about on this phone.
///
/// With the real backend this is just a cache that keeps the UI steady between refreshes.
/// With stubs it's the whole store, which is what lets the propose → accept → calendar
/// flow be demoed and rehearsed before the backend is live.
actor MeetupBook {
    static let shared = MeetupBook()

    private var byID: [String: Meetup] = [:]

    func record(_ meetup: Meetup) {
        byID[meetup.id] = meetup
    }

    func record(_ meetups: [Meetup]) {
        for m in meetups { byID[m.id] = m }
    }

    func find(_ id: String) -> Meetup? { byID[id] }

    func all(for pid: String) -> [Meetup] {
        byID.values
            .filter { $0.a == pid || $0.b == pid }
            .sorted { $0.start < $1.start }
    }

    func between(_ a: String, _ b: String) -> [Meetup] {
        byID.values
            .filter { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }
            .sorted { $0.start < $1.start }
    }
}
