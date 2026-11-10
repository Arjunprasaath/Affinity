// RadarView.swift — the Orbit radar: people near you as dots, matches glow. Owner: Jenish.

import SwiftUI

struct RadarView: View {
    @Environment(AppState.self) private var appState

    @State private var results: [String: RadarResult] = [:]
    @State private var selectedPeer: NearbyPeer?
    @State private var findTarget: NearbyPeer?
    @State private var showList = false

    private var proximity: ProximityManager { appState.proximity }
    private var status: PresenceStatus { appState.profile?.status ?? .green }

    var body: some View {
        @Bindable var proximity = appState.proximity
        NavigationStack {
            VStack(spacing: 16) {
                statusPicker
                if status == .red {
                    invisibleState
                } else if showList {
                    peerList
                } else {
                    RadarCanvas(
                        peers: proximity.sortedPeers,
                        results: results,
                        focusPid: appState.radarFocusPid,
                        onTap: { selectedPeer = $0 }
                    )
                    .overlay(alignment: .bottom) { emptyHint }
                }
                footer
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .navigationTitle("Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Demo people", isOn: $proximity.useDemoPeers)
                        Toggle("List view", isOn: $showList)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Radar options")
                }
                ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() }
            }
            .sheet(item: $selectedPeer) { peer in
                PersonSheet(peer: peer, result: results[peer.pid]) {
                    selectedPeer = nil
                    findTarget = peer
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $findTarget) { peer in
                FindView(pid: peer.pid, name: peer.name)
            }
            // Refresh when people come and go, and whenever the Radar tab is opened (new matches).
            .task(id: "\(Set(proximity.peers.keys).hashValue)-\(appState.selectedTab == .orbit)") {
                await refreshResults()
            }
        }
    }

    // MARK: - Pieces

    private var statusPicker: some View {
        Picker("Your status", selection: Binding(
            get: { status },
            set: { newValue in Task { await appState.setStatus(newValue) } }
        )) {
            ForEach(PresenceStatus.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    private var invisibleState: some View {
        ContentUnavailableView {
            Label("You're invisible", systemImage: "eye.slash")
        } description: {
            Text("Nobody can see you on their radar, and you can't see them. Switch to Open to chat or Ask first to come back.")
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyHint: some View {
        if matchedPeers.isEmpty && proximity.isRunning {
            Label("None of your matches are nearby yet.", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
    }

    private var peerList: some View {
        List(matchedPeers) { peer in
            Button {
                selectedPeer = peer
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(TierStyle(results[peer.pid]?.tier).color)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.name).foregroundStyle(.primary)
                        if let reason = results[peer.pid]?.reason {
                            Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(peer.distanceText).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(peer.accessibilityDescription(tier: results[peer.pid]?.tier))
        }
        .listStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(proximity.capability.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = proximity.lastError {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }

    /// Only people you've mutually matched with appear on the radar, closest first.
    private var matchedPeers: [NearbyPeer] {
        proximity.sortedPeers
            .filter { results[$0.pid]?.tier == .match }
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
    }

    /// Matches first, then strong, good, weak; closest first within a tier.
    private var rankedPeers: [NearbyPeer] {
        proximity.sortedPeers.sorted {
            let a = results[$0.pid]?.tier ?? .weak
            let b = results[$1.pid]?.tier ?? .weak
            if a != b { return a < b }
            return ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude)
        }
    }

    /// Glow tiers from the backend. Re-runs when the set of nearby people changes, then every 30s.
    private func refreshResults() async {
        guard let me = appState.profile?.pid else { return }
        try? await Task.sleep(for: .seconds(1))   // debounce while people come and go
        while !Task.isCancelled {
            let others = Array(proximity.peers.keys)
            if let fetched = try? await APIClient.shared.radarMatch(me: me, others: others) {
                results = Dictionary(fetched.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}

// MARK: - Radar canvas

struct RadarCanvas: View {
    let peers: [NearbyPeer]
    let results: [String: RadarResult]
    let focusPid: String?
    let onTap: (NearbyPeer) -> Void

    /// Ring edges in meters. Anything farther, or with no distance yet, sits on the outer ring.
    static let rings: [(meters: Float, label: String)] = [(2, "2 m"), (5, "5 m"), (15, "15 m")]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - 24
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ForEach(Array(Self.rings.enumerated()), id: \.offset) { index, ring in
                    let r = radius * CGFloat(index + 1) / CGFloat(Self.rings.count)
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        .frame(width: r * 2, height: r * 2)
                        .position(center)
                    Text(ring.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: center.x + 4, y: center.y - r + 10)
                }

                // You, in the center. "Ahead" is the top of the screen.
                Image(systemName: "location.north.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .position(center)
                    .accessibilityLabel("You")

                ForEach(peers) { peer in
                    let point = position(for: peer, center: center, radius: radius)
                    PeerDot(
                        peer: peer,
                        tier: results[peer.pid]?.tier,
                        isFocused: peer.pid == focusPid
                    )
                    .position(point)
                    .animation(.easeInOut(duration: 0.4), value: point)
                    // Only matches open a card; everyone else stays an anonymous dot.
                    .onTapGesture { if results[peer.pid]?.tier == .match { onTap(peer) } }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func position(for peer: NearbyPeer, center: CGPoint, radius: CGFloat) -> CGPoint {
        let fraction = Self.ringFraction(for: peer.distance)
        let angle = peer.bearing ?? Self.stableAngle(for: peer.pid)
        let r = radius * CGFloat(fraction)
        return CGPoint(x: center.x + r * CGFloat(sin(angle)), y: center.y - r * CGFloat(cos(angle)))
    }

    /// Maps meters onto the three equal-width rings: 0–2 m, 2–5 m, 5–15 m.
    static func ringFraction(for distance: Float?) -> Double {
        guard let d = distance else { return 0.96 }
        let edges: [Float] = [0] + rings.map(\.meters)
        for i in 1..<edges.count where d <= edges[i] {
            let within = Double((d - edges[i - 1]) / (edges[i] - edges[i - 1]))
            return (Double(i - 1) + within) / Double(rings.count)
        }
        return 0.96
    }

    /// Phones without direction still get a consistent spot for each person.
    static func stableAngle(for pid: String) -> Double {
        let sum = pid.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) * .pi / 180
    }
}

struct PeerDot: View {
    let peer: NearbyPeer
    let tier: RadarTier?
    let isFocused: Bool

    @State private var pulse = false

    private var style: TierStyle { TierStyle(tier) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if tier == .match || isFocused {
                    Circle()
                        .fill(style.color.opacity(0.25))
                        .frame(width: style.size * 2.2, height: style.size * 2.2)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                }
                Circle()
                    .fill(style.color.opacity(style.opacity))
                    .frame(width: style.size, height: style.size)
                if peer.status == .yellow && tier == .match {
                    Circle()
                        .stroke(Color.orange, lineWidth: 2.5)
                        .frame(width: style.size + 6, height: style.size + 6)
                }
                if isFocused {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: style.size + 14, height: style.size + 14)
                }
            }
            if style.showsName || isFocused {
                Text(peer.firstName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .contentShape(Rectangle().inset(by: -12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier == .match ? peer.accessibilityDescription(tier: tier) : "Someone nearby")
        .accessibilityAddTraits(tier == .match ? .isButton : [])
    }
}

/// How each match tier looks on the radar.
struct TierStyle {
    let color: Color
    let size: CGFloat
    let opacity: Double
    let showsName: Bool

    init(_ tier: RadarTier?) {
        switch tier {
        case .match: (color, size, opacity, showsName) = (.green, 26, 1, true)
        // People you haven't matched with: a plain dot, no name, no colour coding.
        case .strong, .good, .weak, nil: (color, size, opacity, showsName) = (.gray, 13, 0.45, false)
        }
    }
}

extension NearbyPeer {
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var distanceText: String {
        guard let distance else { return "Nearby" }
        return distance < 10 ? String(format: "%.1f m", distance) : String(format: "%.0f m", distance)
    }

    func accessibilityDescription(tier: RadarTier?) -> String {
        var parts = [name]
        switch tier {
        case .match: parts.append("your match")
        case .strong: parts.append("strong match")
        case .good: parts.append("good match")
        default: break
        }
        if let distance { parts.append("about \(Int(distance.rounded())) meters") } else { parts.append("nearby") }
        if let bearing {
            let degrees = bearing * 180 / .pi
            let side = abs(degrees) < 25 ? "ahead" : (degrees > 0 ? "to your right" : "to your left")
            parts.append(side)
        }
        if status == .yellow { parts.append("ask first") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    RadarView().environment(AppState())
}
