// OnboardingView.swift — minimal sign-up (name, LinkedIn, GitHub, two questions), then confirm topics.

import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var name = ""
    @State private var linkedin = ""
    @State private var github = ""
    @State private var interests = ""
    @State private var lookingFor = ""

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
            .navigationTitle(createdProfile == nil ? "" : "Your topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { DevSettingsButton() }
            }
        }
    }

    // Minimal sign-up: name, LinkedIn, GitHub and two questions. Everything else is inferred.
    private var form: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    // Neutral icon until there's a name or GitHub photo to show (no "?").
                    if name.isEmpty && github.isEmpty {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(Theme.accent.opacity(0.35))
                            .accessibilityHidden(true)
                    } else {
                        Avatar(name: name.isEmpty ? " " : name, github: github, size: 80)
                    }
                    Text("Affinity")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.brand)
                    Text("Find your people at the conference")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                VStack(spacing: 0) {
                    LabeledField(label: "Name", placeholder: "Your name", text: $name)
                        .textContentType(.name)
                        .padding(.vertical, 12)
                    Divider()
                    LabeledField(label: "LinkedIn", placeholder: "linkedin.com/in/you", text: $linkedin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.vertical, 12)
                    Divider()
                    LabeledField(label: "GitHub", placeholder: "username", text: $github)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                question("What are you into?", placeholder: "LLMs, pretraining, fine-tuning", text: $interests, color: Theme.accent)
                question("What do you want from this conference?", placeholder: "Meet people training LLMs at scale", text: $lookingFor, color: Theme.accent)

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(.white) }
                        Text(isSubmitting ? "Building your profile…" : "Continue").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(Theme.brand, in: Capsule())
                }
                .disabled(isSubmitting)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button("Use demo profile") { Task { await useDemoProfile() } }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.wash.ignoresSafeArea())
    }

    private func question(_ title: String, placeholder: String, text: Binding<String>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator)))
        }
    }

    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Add your name."
            return
        }
        guard interests.nilIfBlank != nil else {
            errorMessage = "Tell us what you're into."
            return
        }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let newProfile = NewProfile(
            name: trimmedName,
            role: nil,
            company: nil,
            pronouns: nil,
            github: github.nilIfBlank,
            linkedin: linkedin.nilIfBlank,
            workingOn: interests.nilIfBlank,
            lookingFor: lookingFor.nilIfBlank,
            offering: nil,
            hereFor: [],
            status: .green
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
                    Text("No topics left.")
                        .foregroundStyle(.secondary)
                }
                ForEach(topics, id: \.self) { topic in
                    HStack {
                        Circle().fill(Theme.color(for: topic)).frame(width: 10, height: 10)
                        Text(topic).foregroundStyle(Theme.color(for: topic))
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
                Text("We'll match you on these")
            } footer: {
                Text("Remove any that don't fit.")
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
