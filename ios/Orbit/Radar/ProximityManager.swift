// ProximityManager.swift — who is physically near me. Owner: Jenish.
//
// Live mode (real iPhones): MultipeerConnectivity finds nearby phones running Orbit over
// Bluetooth + peer-to-peer Wi-Fi; NearbyInteraction (UWB) measures distance and direction.
// Demo mode (Simulator, or the stage fallback): fake people who drift closer and farther.
//
// Nothing here talks to the backend. Locations never leave the phone.

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Observation
import simd

struct NearbyPeer: Identifiable, Hashable {
    let pid: String
    var name: String
    var status: PresenceStatus
    /// Meters, from UWB. nil means "nearby" (in Bluetooth range) with no measurement yet.
    var distance: Float?
    /// Unit vector toward the peer in the phone's coordinates (+x right, -z straight ahead).
    var direction: SIMD3<Float>?
    var isDemo = false

    var id: String { pid }

    /// Horizontal angle in radians: 0 = straight ahead, positive = to the right.
    var bearing: Double? {
        guard let direction else { return nil }
        return Double(atan2(direction.x, -direction.z))
    }
}

enum ProximityCapability: Equatable {
    case demo, distanceAndDirection, distanceOnly, nearbyOnly

    var label: String {
        switch self {
        case .demo: "Demo people: simulated, not real attendees"
        case .distanceAndDirection: "Live: distance and direction (UWB)"
        case .distanceOnly: "Live: distance only on this iPhone"
        case .nearbyOnly: "Live: nearby only (this iPhone has no UWB)"
        }
    }
}

@MainActor
@Observable
final class ProximityManager {
    private(set) var peers: [String: NearbyPeer] = [:]
    private(set) var isRunning = false
    private(set) var lastError: String?

    /// On in the Simulator (no Bluetooth or UWB there), off on real iPhones. Toggle from the radar menu.
    var useDemoPeers: Bool {
        didSet { if oldValue != useDemoPeers { restart() } }
    }

    @ObservationIgnored private var engine: MultipeerNearbyEngine?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var identity: (pid: String, name: String, status: PresenceStatus)?

    init() {
        #if targetEnvironment(simulator)
        useDemoPeers = true
        #else
        useDemoPeers = false
        #endif
    }

    var capability: ProximityCapability {
        if useDemoPeers { return .demo }
        let caps = NISession.deviceCapabilities
        if caps.supportsDirectionMeasurement { return .distanceAndDirection }
        if caps.supportsPreciseDistanceMeasurement { return .distanceOnly }
        return .nearbyOnly
    }

    /// Closest first; people with no distance yet go last.
    var sortedPeers: [NearbyPeer] {
        peers.values.sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
    }

    func start(pid: String, name: String, status: PresenceStatus) {
        identity = (pid, name, status)
        restart()
    }

    /// Red stops advertising and browsing entirely, so you vanish from everyone's radar.
    func updateStatus(_ status: PresenceStatus) {
        guard var identity, identity.status != status else { return }
        identity.status = status
        self.identity = identity
        restart()
    }

    func stop() {
        engine?.stop()
        engine = nil
        demoTask?.cancel()
        demoTask = nil
        peers = [:]
        isRunning = false
    }

    private func restart() {
        stop()
        lastError = nil
        guard let identity, identity.status != .red else { return }
        isRunning = true
        if useDemoPeers {
            startDemo()
        } else {
            startLive(identity)
        }
    }

    // MARK: - Live

    private func startLive(_ me: (pid: String, name: String, status: PresenceStatus)) {
        let engine = MultipeerNearbyEngine(pid: me.pid, name: me.name, status: me.status)
        engine.onPeerUpdate = { [weak self] peer in
            if peer.status == .red {
                self?.peers[peer.pid] = nil
            } else {
                self?.peers[peer.pid] = peer
            }
        }
        engine.onPeerLost = { [weak self] pid in self?.peers[pid] = nil }
        engine.onError = { [weak self] message in self?.lastError = message }
        engine.start()
        self.engine = engine
    }

    // MARK: - Demo

    private func startDemo() {
        demoTask = Task { [weak self] in
            let startedAt = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(startedAt)
                self?.peers = Self.demoPeers(at: t)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// Four seeded personas (pids match Core/Stubs). Jensen walks toward you and back so Find has something to do.
    nonisolated static func demoPeers(at t: Double) -> [String: NearbyPeer] {
        func peer(_ pid: String, _ name: String, _ status: PresenceStatus, distance: Double, bearing: Double) -> NearbyPeer {
            NearbyPeer(
                pid: pid, name: name, status: status,
                distance: Float(distance),
                direction: SIMD3(Float(sin(bearing)), 0, Float(-cos(bearing))),
                isDemo: true
            )
        }
        // Mei is the demo's first match: she walks toward you and back so Find has something to do.
        let meiDistance = 0.8 + 7.2 * (0.5 + 0.5 * cos(t / 5))
        let list = [
            peer("p_mei", "Mei Lin", .green, distance: meiDistance, bearing: 0.6 * sin(t / 7) + 0.5),
            peer("p_jensen", "Jensen Park", .green, distance: 6.0 + 0.5 * sin(t / 6), bearing: 1.2),
            peer("p_satya", "Satya Rao", .green, distance: 3.6 + 0.4 * sin(t / 3), bearing: -1.9),
            peer("p_mark", "Mark Ellis", .yellow, distance: 8.5 + 1.5 * sin(t / 4), bearing: 2.6),
            peer("p_sam", "Sam Lee", .green, distance: 12.5, bearing: -0.4 + 0.1 * sin(t / 9)),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
    }
}

// MARK: - Multipeer + NearbyInteraction

/// Runs on its own serial queue; reports to the main actor through the callbacks.
final class MultipeerNearbyEngine: NSObject {
    static let serviceType = "orbit-cnh"   // must match NSBonjourServices in Config/Info.plist

    var onPeerUpdate: (@MainActor (NearbyPeer) -> Void)?
    var onPeerLost: (@MainActor (String) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    private let myPid: String
    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let queue = DispatchQueue(label: "orbit.proximity")

    private var latest: [MCPeerID: NearbyPeer] = [:]
    private var niSessions: [MCPeerID: NISession] = [:]
    private var peerForSession: [ObjectIdentifier: MCPeerID] = [:]
    private var configurations: [ObjectIdentifier: NINearbyPeerConfiguration] = [:]

    private struct Envelope: Codable {
        var token: Data?
    }

    init(pid: String, name: String, status: PresenceStatus) {
        myPid = pid
        myPeerID = MCPeerID(displayName: String(pid.prefix(60)))
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        let info = ["pid": pid, "name": String(name.prefix(40)), "status": status.rawValue]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        queue.async {
            self.niSessions.values.forEach { $0.invalidate() }
            self.niSessions.removeAll()
            self.peerForSession.removeAll()
            self.configurations.removeAll()
            self.latest.removeAll()
        }
    }

    // MARK: Helpers (always called on `queue`)

    private func emit(_ peer: NearbyPeer) {
        let callback = onPeerUpdate
        Task { @MainActor in callback?(peer) }
    }

    private func emitLost(_ pid: String) {
        let callback = onPeerLost
        Task { @MainActor in callback?(pid) }
    }

    private func emitError(_ message: String) {
        let callback = onError
        Task { @MainActor in callback?(message) }
    }

    private func niSession(for peerID: MCPeerID) -> NISession? {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else { return nil }
        if let existing = niSessions[peerID] { return existing }
        let ni = NISession()
        ni.delegate = self
        ni.delegateQueue = queue
        niSessions[peerID] = ni
        peerForSession[ObjectIdentifier(ni)] = peerID
        return ni
    }

    private func tearDownNI(for peerID: MCPeerID) {
        guard let ni = niSessions.removeValue(forKey: peerID) else { return }
        peerForSession[ObjectIdentifier(ni)] = nil
        configurations[ObjectIdentifier(ni)] = nil
        ni.invalidate()
    }

    private func sendToken(to peerID: MCPeerID) {
        guard let ni = niSession(for: peerID), let token = ni.discoveryToken else { return }
        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            let data = try JSONEncoder().encode(Envelope(token: tokenData))
            try session.send(data, toPeers: [peerID], with: .reliable)
        } catch {
            emitError("Couldn't start distance measuring: \(error.localizedDescription)")
        }
    }
}

extension MultipeerNearbyEngine: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        queue.async {
            guard let info, let pid = info["pid"], pid != self.myPid else { return }
            let status = PresenceStatus(rawValue: info["status"] ?? "") ?? .green
            var peer = self.latest[peerID] ?? NearbyPeer(pid: pid, name: info["name"] ?? "Someone", status: status)
            peer.name = info["name"] ?? peer.name
            peer.status = status
            self.latest[peerID] = peer
            self.emit(peer)
            // Only one side invites, so the two phones don't race each other.
            if self.myPid < pid {
                browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        queue.async {
            self.tearDownNI(for: peerID)
            if let peer = self.latest.removeValue(forKey: peerID) {
                self.emitLost(peer.pid)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        queue.async { self.emitError("Can't look for nearby people: \(error.localizedDescription). Check Local Network permission.") }
    }
}

extension MultipeerNearbyEngine: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        queue.async { self.emitError("Can't make you visible: \(error.localizedDescription). Check Local Network permission.") }
    }
}

extension MultipeerNearbyEngine: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        queue.async {
            switch state {
            case .connected:
                self.sendToken(to: peerID)
            case .notConnected:
                self.tearDownNI(for: peerID)
                if var peer = self.latest[peerID] {
                    peer.distance = nil
                    peer.direction = nil
                    self.latest[peerID] = peer
                    self.emit(peer)
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        queue.async {
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  let tokenData = envelope.token,
                  let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData),
                  let ni = self.niSession(for: peerID) else { return }
            let configuration = NINearbyPeerConfiguration(peerToken: token)
            self.configurations[ObjectIdentifier(ni)] = configuration
            ni.run(configuration)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerNearbyEngine: NISessionDelegate {
    // NISession delegate callbacks arrive on `queue` (delegateQueue).

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerID = peerForSession[ObjectIdentifier(session)],
              var peer = latest[peerID],
              let object = nearbyObjects.first else { return }
        if let distance = object.distance { peer.distance = distance }
        peer.direction = object.direction
        latest[peerID] = peer
        emit(peer)
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // Timeout = briefly out of UWB range; ask again. peerEnded = they closed the app.
        if reason == .timeout, let configuration = configurations[ObjectIdentifier(session)] {
            session.run(configuration)
        }
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let configuration = configurations[ObjectIdentifier(session)] {
            session.run(configuration)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let peerID = peerForSession[ObjectIdentifier(session)] else { return }
        tearDownNI(for: peerID)
        emitError("Distance measuring stopped: \(error.localizedDescription)")
        // Rebuild and resend our token if we're still connected.
        if self.session.connectedPeers.contains(peerID) {
            sendToken(to: peerID)
        }
    }
}
