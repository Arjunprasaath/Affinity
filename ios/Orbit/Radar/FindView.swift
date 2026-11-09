// FindView.swift — full-screen arrow and distance, like AirTag precision finding. Owner: Jenish.

import SwiftUI

struct FindView: View {
    let pid: String
    let name: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var peer: NearbyPeer? { appState.proximity.peers[pid] }
    private var isClose: Bool { (peer?.distance ?? .greatestFiniteMagnitude) < 1.5 }

    var body: some View {
        ZStack {
            (isClose ? Color.green : Color(.systemBackground))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: isClose)

            VStack(spacing: 24) {
                Text("Finding \(name)")
                    .font(.title2.bold())
                    .padding(.top, 32)

                Spacer()

                if let bearing = peer?.bearing {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 180, weight: .bold))
                        .rotationEffect(.radians(bearing))
                        .animation(.easeOut(duration: 0.3), value: bearing)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: peer == nil ? "questionmark.circle" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 140, weight: .regular))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: peer != nil)
                        .accessibilityHidden(true)
                }

                Text(peer?.distanceText ?? "Out of range")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: peer?.distanceText)

                Text(hint)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.bottom, 24)
            }
            .foregroundStyle(isClose ? Color.white : Color.primary)
        }
        .sensoryFeedback(.success, trigger: isClose) { _, close in close }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(peer.map { $0.accessibilityDescription(tier: nil) } ?? "\(name) is out of range")
    }

    private var hint: String {
        guard let peer else { return "\(name) isn't in range. Walk around a bit, or ask them to open Orbit." }
        if isClose { return "You're here. Say hi to \(peer.firstName)!" }
        if peer.distance == nil { return "\(peer.firstName) is nearby. Distance shows up once you're both a little closer." }
        if peer.bearing == nil { return "Follow the distance. This iPhone can't show direction." }
        return "Point the top of your phone where you're walking."
    }
}
