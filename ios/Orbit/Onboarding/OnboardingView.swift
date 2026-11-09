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
            // Photo preview: pulled from GitHub as soon as a username is typed.
            Section {
                VStack(spacing: 8) {
                    Avatar(name: name.isEmpty ? "?" : name, github: github, size: 84)
                    Text(github.isEmpty ? "Add your GitHub to use your photo" : "Photo from GitHub")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledField(label: "Name", placeholder: "Your name", text: $name)
                    .textContentType(.name)
                LabeledField(label: "Role", placeholder: "Platform engineer", text: $role)
                LabeledField(label: "GitHub", placeholder: "username", text: $github)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("What are you working on?") {
                TextField("Migrating 40 clusters to Cilium", text: $workingOn, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                DisclosureGroup("Better matches (optional)") {
                    LabeledField(label: "Company", placeholder: "Optional", text: $company)
                    LabeledField(label: "Pronouns", placeholder: "Optional", text: $pronouns)
                    TextField("Looking for: people running GPUs at scale", text: $lookingFor, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Can help with: KServe, autoscaling", text: $offering, axis: .vertical)
                        .lineLimit(1...3)
                    hereForPicker
                    Picker("On the radar", selection: $status) {
                        ForEach(PresenceStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
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

    /// "Here for" as one row of tappable chips instead of five list rows.
    private var hereForPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Here for").font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HereFor.allCases) { option in
                        let isOn = hereFor.contains(option)
                        Button {
                            if isOn { hereFor.remove(option) } else { hereFor.insert(option) }
                        } label: {
                            Text(option.label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(isOn ? Color.white : Color.primary)
                                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
            Section {
                HStack(spacing: 14) {
                    Avatar(name: profile.name, github: profile.github, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.headline)
                        if let summary = profile.summary {
                            Text(summary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
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
