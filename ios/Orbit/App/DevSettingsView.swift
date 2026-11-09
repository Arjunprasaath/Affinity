// DevSettingsView.swift — switch between stub data and the live backend without rebuilding. Owner: Jenish.

import SwiftUI

struct DevSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var baseURL = AppConfig.apiBaseURL.absoluteString
    @State private var useStubs = AppConfig.useStubs
    @State private var connectionMessage: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Use stub data", isOn: $useStubs)
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Stub data comes from the JSON files bundled in the app. Turn it off once the backend is deployed.")
                }

                Section {
                    Button(isChecking ? "Checking…" : "Check connection") {
                        Task { await checkConnection() }
                    }
                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.profile != nil {
                    Section {
                        Button("Sign out", role: .destructive) {
                            appState.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        AppConfig.setAPIBaseURL(baseURL)
        AppConfig.useStubs = useStubs
    }

    private func checkConnection() async {
        save()
        isChecking = true
        defer { isChecking = false }
        do {
            let health = try await APIClient.shared.health()
            connectionMessage = health.ok ? "Connected to \(AppConfig.apiBaseURL.absoluteString)" : "The server says it isn't healthy."
        } catch {
            connectionMessage = error.localizedDescription
        }
    }
}

/// Gear button that opens Developer settings. Drop it into any toolbar.
struct DevSettingsButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Developer settings")
        .sheet(isPresented: $isPresented) {
            DevSettingsView()
        }
    }
}
