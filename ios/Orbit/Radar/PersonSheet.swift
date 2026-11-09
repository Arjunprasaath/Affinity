// PersonSheet.swift — who a dot on the radar is, and why you might talk. Owner: Jenish.

import SwiftUI

struct PersonSheet: View {
    /// Snapshot from when the dot was tapped; `live` below keeps distance and status current.
    let peer: NearbyPeer
    let result: RadarResult?
    let onFind: () -> Void

    @Environment(AppState.self) private var appState
    @State private var profile: Profile?

    private var live: NearbyPeer { appState.proximity.peers[peer.pid] ?? peer }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(peer.name).font(.title2.bold())
                        if let subtitle {
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            StatusBadge(status: live.status)
                            Text(appState.proximity.peers[peer.pid] == nil ? "Out of range" : live.distanceText)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .animation(.default, value: live.distanceText)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let reason = result?.reason {
                    Section(result?.tier == .match ? "You matched" : "Why you might talk") {
                        Text(reason)
                    }
                }

                if let workingOn = profile?.workingOn {
                    Section("Working on") { Text(workingOn) }
                }

                if let hereFor = profile?.hereFor, !hereFor.isEmpty {
                    Section("Here for") {
                        Text(hereFor.map { HereFor(rawValue: $0)?.label ?? $0 }.joined(separator: " · "))
                    }
                }

                if live.status == .yellow {
                    Section {
                        Label("\(peer.firstName) asked people to check before walking over.", systemImage: "hand.raised")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(action: onFind) {
                        Label("Find \(peer.firstName)", systemImage: "location.north.line.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                profile = try? await APIClient.shared.profile(pid: peer.pid)
            }
        }
    }

    private var subtitle: String? {
        let parts = [profile?.role, profile?.company].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct StatusBadge: View {
    let status: PresenceStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .green: .green
        case .yellow: .orange
        case .red: .red
        }
    }
}
