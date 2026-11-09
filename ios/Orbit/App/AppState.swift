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

    @ObservationIgnored private let pidKey = "orbit.currentPid"

    func restoreSession() async {
        defer { isRestoring = false }
        guard let pid = UserDefaults.standard.string(forKey: pidKey) else { return }
        profile = try? await APIClient.shared.profile(pid: pid)
    }

    func signIn(_ profile: Profile) {
        self.profile = profile
        UserDefaults.standard.set(profile.pid, forKey: pidKey)
    }

    func signOut() {
        profile = nil
        radarFocusPid = nil
        selectedTab = .talks
        UserDefaults.standard.removeObject(forKey: pidKey)
    }

    /// Jump to the Orbit tab with this person highlighted. Call from MatchDetailView.
    func findOnRadar(pid: String) {
        radarFocusPid = pid
        selectedTab = .orbit
    }
}
