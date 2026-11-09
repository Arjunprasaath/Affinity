// OrbitApp.swift — app entry point. Owner: Jenish.

import SwiftUI

@main
struct OrbitApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Theme.accent)
                .task { await appState.restoreSession() }
        }
    }
}

/// Shows onboarding until there's a profile, then the tab bar.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isRestoring {
            ProgressView()
        } else if appState.profile == nil {
            OnboardingView()
        } else {
            RootTabView()
        }
    }
}

struct RootTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            TalksDeckView()
                .tabItem { Label("Talks", systemImage: "rectangle.stack") }
                .tag(AppTab.talks)
            MyCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            PeopleDeckView()
                .tabItem { Label("People", systemImage: "person.2") }
                .tag(AppTab.people)
            MatchesListView()
                .tabItem { Label("Matches", systemImage: "heart.circle") }
                .tag(AppTab.matches)
            RadarView()
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.orbit)
        }
    }
}
