// OnboardingView.swift — create your profile, then review the topic tags. Owner: Jenish.

import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var role = ""
    @State private var company = ""
    @State private var pronouns = ""
    @State private var github = ""
    @State private var workingOn = ""
    @State private var lookingFor = ""
    @State private var offering = ""
    @State private var hereFor: Set<HereFor> = [.learning]
    @State private var status: PresenceStatus = .green

    @State private var createdProfile: Profile?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let createdProfile {
                    TagReviewView(profile: createdProfile) { confirmed in
                        appState.signIn(confirmed)
                    }
                } else {
                    form
                }
            }
            .navigationTitle(createdProfile == nil ? "Welcome to Orbit" : "Your tags")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() }
            }
        }
    }

    private var form: some View {
        Form {
            Section("About you") {
                LabeledField(label: "Name", placeholder: "Your name", text: $name)
                    .textContentType(.name)
                LabeledField(label: "Role", placeholder: "Platform engineer", text: $role)
                LabeledField(label: "Company", placeholder: "Optional", text: $company)
                LabeledField(label: "Pronouns", placeholder: "Optional", text: $pronouns)
                LabeledField(label: "GitHub", placeholder: "username", text: $github)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("What are you working on?") {
                TextField("Migrating 40 clusters to Cilium", text: $workingOn, axis: .vertical)
            }
            Section("What are you looking for here?") {
                TextField("People running GPU workloads at scale", text: $lookingFor, axis: .vertical)
            }
            Section("What could you help someone with?") {
                TextField("KServe deployment, GPU autoscaling", text: $offering, axis: .vertical)
            }

            Section("Here for") {
                ForEach(HereFor.allCases) { option in
                    Button {
                        if hereFor.contains(option) { hereFor.remove(option) } else { hereFor.insert(option) }
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if hereFor.contains(option) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(hereFor.contains(option) ? .isSelected : [])
                }
            }

            Section {
                Picker("Status", selection: $status) {
                    ForEach(PresenceStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("On the radar")
            } footer: {
                Text("Invisible hides you from everyone's radar. You can change this any time.")
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                            Text("Building your profile…")
                        } else {
                            Text("Create profile").bold()
                        }
                        Spacer()
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Use the demo profile") {
                    Task { await useDemoProfile() }
                }
            } footer: {
                Text("Skips onboarding with a sample profile. For building and testing.")
            }
        }
    }

    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter your name first."
            return
        }
        guard !workingOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Add a line about what you're working on. Matching depends on it."
            return
        }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let newProfile = NewProfile(
            name: trimmedName,
            role: role.nilIfBlank,
            company: company.nilIfBlank,
            pronouns: pronouns.nilIfBlank,
            github: github.nilIfBlank,
            workingOn: workingOn.nilIfBlank,
            lookingFor: lookingFor.nilIfBlank,
            offering: offering.nilIfBlank,
            hereFor: HereFor.allCases.filter(hereFor.contains).map(\.rawValue),
            status: status
        )
        do {
            createdProfile = try await APIClient.shared.createProfile(newProfile)
        } catch {
            errorMessage = "Couldn't create your profile. \(error.localizedDescription)"
        }
    }

    private func useDemoProfile() async {
        do {
            var demo: Profile = try APIClient.stub("stub_profile")
            demo.pid = APIClient.randomPid()   // unique per phone so two demo phones still see each other
            appState.signIn(demo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shows the tags the backend extracted; the user removes wrong ones, then confirms.
struct TagReviewView: View {
    let profile: Profile
    let onConfirm: (Profile) -> Void

    @State private var topics: [String]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profile: Profile, onConfirm: @escaping (Profile) -> Void) {
        self.profile = profile
        self.onConfirm = onConfirm
        _topics = State(initialValue: profile.topics)
    }

    var body: some View {
        Form {
            if let summary = profile.summary {
                Section("Summary") { Text(summary) }
            }
            Section {
                if topics.isEmpty {
                    Text("No tags left. Add more detail to your profile for better matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(topics, id: \.self) { topic in
                    HStack {
                        Text(topic)
                        Spacer()
                        Button {
                            topics.removeAll { $0 == topic }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(topic)")
                    }
                }
            } header: {
                Text("Topics we found")
            } footer: {
                Text("Remove anything that's wrong. These drive your talk and people matches.")
            }

            Section {
                Button {
                    Task { await confirm() }
                } label: {
                    HStack {
                        Spacer()
                        Text(isSaving ? "Saving…" : "Looks good").bold()
                        Spacer()
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func confirm() async {
        guard topics != profile.topics else {
            onConfirm(profile)
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await APIClient.shared.updateProfile(pid: profile.pid, ProfilePatch(topics: topics))
            onConfirm(updated)
        } catch {
            errorMessage = "Couldn't save your tags. \(error.localizedDescription)"
        }
    }
}

/// A form row with a visible label on the left and the text field on the right.
struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text, prompt: Text(placeholder))
                .multilineTextAlignment(.trailing)
        }
    }
}

extension String {
    /// nil for empty or whitespace-only strings, so optional fields are omitted from requests.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    OnboardingView().environment(AppState())
}
