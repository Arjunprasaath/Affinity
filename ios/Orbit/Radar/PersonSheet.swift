// PersonSheet.swift — who a dot on the radar is, and why you might talk. Owner: Jenish.
// Fits in the half-height sheet: photo + who, one "why" line, two short details, Find pinned at the bottom.

import SwiftUI

struct PersonSheet: View {
    /// Snapshot from when the dot was tapped; `live` below keeps distance and status current.
    let peer: NearbyPeer
    let result: RadarResult?
    let onFind: () -> Void

    @Environment(AppState.self) private var appState
    @State private var profile: Profile?

    private var live: NearbyPeer { appState.proximity.peers[peer.pid] ?? peer }
    private var inRange: Bool { appState.proximity.peers[peer.pid] != nil }
    private var isMatch: Bool { result?.tier == .match }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let reason = result?.reason {
                    Label {
                        Text(reason).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: isMatch ? "checkmark.seal.fill" : "sparkles")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isMatch ? Color.green : Color.accentColor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (isMatch ? Color.green : Color.accentColor).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                if let workingOn = profile?.workingOn, !workingOn.isEmpty {
                    detail("Working on") {
                        Text(workingOn).font(.subheadline).lineLimit(2)
                    }
                }

                if let hereFor = profile?.hereFor, !hereFor.isEmpty {
                    detail("Here for") {
                        ChipRow(items: hereFor.map { HereFor(rawValue: $0)?.label ?? $0 }, tint: .orange, limit: 3)
                    }
                }

                if live.status == .yellow {
                    Label("\(peer.firstName) asked people to check before walking over", systemImage: "hand.raised.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { findButton }
        .task {
            profile = try? await APIClient.shared.profile(pid: peer.pid)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(name: peer.name, github: profile?.github, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    StatusBadge(status: live.status)
                    Label(inRange ? live.distanceText : "Out of range", systemImage: "location.fill")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: live.distanceText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var findButton: some View {
        Button(action: onFind) {
            Label("Find \(peer.firstName)", systemImage: "location.north.line.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func detail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var subtitle: String? {
        let parts = [profile?.role, profile?.company].compactMap { $0 }.filter { !$0.isEmpty }
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
