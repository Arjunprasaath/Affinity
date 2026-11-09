// AppState.swift — app-wide state shared by every screen. Owner: Jenish.
//
// Read it in any view with:  @Environment(AppState.self) private var appState
// The signed-in user's pid is `appState.profile?.pid`.

import Foundation
import Observation

enum AppTab: Hashable {
    case talks, calendar, people, matches, orbit
}

@MainActor
@Observable
final class AppState {
    var profile: Profile?
    var isRestoring = true
    var selectedTab: AppTab = .talks

    /// Set by "Find on radar" so the Orbit tab opens focused on that person.
    var radarFocusPid: String?

    /// Who is physically near me. Runs while signed in, unless status is red.
    let proximity = ProximityManager()

    @ObservationIgnored private let pidKey = "orbit.currentPid"

    func restoreSession() async {
        defer { isRestoring = false }
        guard let pid = UserDefaults.standard.string(forKey: pidKey) else { return }
        profile = try? await APIClient.shared.profile(pid: pid)
        startProximity()
    }

    func signIn(_ profile: Profile) {
        self.profile = profile
        UserDefaults.standard.set(profile.pid, forKey: pidKey)
        startProximity()
    }

    func signOut() {
        proximity.stop()
        profile = nil
        radarFocusPid = nil
        selectedTab = .talks
        UserDefaults.standard.removeObject(forKey: pidKey)
    }

    /// 🟢 / 🟡 / 🔴. Red makes you invisible immediately; the backend is told too.
    func setStatus(_ status: PresenceStatus) async {
        guard let pid = profile?.pid, profile?.status != status else { return }
        profile?.status = status
        proximity.updateStatus(status)
        _ = try? await APIClient.shared.updateProfile(pid: pid, ProfilePatch(status: status))
    }

    private func startProximity() {
        guard let profile else { return }
        proximity.start(pid: profile.pid, name: profile.name, status: profile.status)
    }

    /// Jump to the Orbit tab with this person highlighted. Call from MatchDetailView.
    func findOnRadar(pid: String) {
        radarFocusPid = pid
        selectedTab = .orbit
    }
}
