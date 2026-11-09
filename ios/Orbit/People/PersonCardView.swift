// PersonCardView.swift — one recommended person as a swipe card. Owner: Teammate C.
//
// Deliberately shows no calendar detail. Shared *talk count* is fine ("3 talks in common"),
// but which talks, and when either of you is free, stays hidden until you both swipe right.

import SwiftUI

struct PersonCardView: View {
    let person: PersonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Who
            HStack(alignment: .center, spacing: 14) {
                Avatar(name: person.name, github: person.github, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if person.sharedTalksCount > 0 {
                        Label(
                            "\(person.sharedTalksCount) talk\(person.sharedTalksCount == 1 ? "" : "s") in common",
                            systemImage: "rectangle.stack.badge.checkmark"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
            }

            // Why (the line that makes you swipe)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                Text(person.reason)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // What
            if let workingOn = person.workingOn, !workingOn.isEmpty {
                field("Working on", workingOn)
            }

            if !person.sharedTopics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You both work on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ChipRow(items: person.sharedTopics, tint: .accentColor, limit: 4)
                }
            }

            if !person.hereFor.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Here for").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ChipRow(items: person.hereFor.map { HereFor(rawValue: $0)?.label ?? $0 }, tint: .orange, limit: 3)
                }
            }

            Spacer(minLength: 0)

            Label("Their schedule stays private until you both swipe right", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .deckCard()
        .accessibilityLabel(accessibilityDescription)
    }

    private var subtitle: String? {
        let parts = [person.role, person.company].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(2)
        }
    }

    private var accessibilityDescription: String {
        var parts = [person.name]
        if let subtitle { parts.append(subtitle) }
        if let workingOn = person.workingOn { parts.append("Working on \(workingOn)") }
        if !person.sharedTopics.isEmpty { parts.append("Shared topics: \(person.sharedTopics.joined(separator: ", "))") }
        parts.append(person.reason)
        if person.sharedTalksCount > 0 { parts.append("\(person.sharedTalksCount) talks in common") }
        return parts.joined(separator: ". ")
    }
}

/// Profile photo from GitHub (github.com/<username>.png) when we have a username,
/// otherwise a coloured initials circle. Nobody uploads a photo in a 60-second onboarding.
struct Avatar: View {
    let name: String
    var github: String? = nil
    var size: CGFloat = 52

    var body: some View {
        if let url = photoURL {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                } else {
                    initialsCircle
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            initialsCircle
        }
    }

    private var photoURL: URL? {
        guard let user = github?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty,
              user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return URL(string: "https://github.com/\(user).png?size=\(Int(size * 3))")
    }

    private var initialsCircle: some View {
        Circle()
            .fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    /// Stable colour per person, so the same dot/avatar colour follows them around the app.
    private var tint: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
        // Swift's hashValue is seeded per process, so sum the scalars instead: the same
        // person keeps the same colour across launches and across both phones.
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[seed % palette.count]
    }
}
