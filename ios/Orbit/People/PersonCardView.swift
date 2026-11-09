// PersonCardView.swift — one recommended person as a swipe card. Owner: Teammate C.
//
// Deliberately shows no calendar detail. Shared *talk count* is fine ("3 talks in common"),
// but which talks, and when either of you is free, stays hidden until you both swipe right.

import SwiftUI

struct PersonCardView: View {
    let person: PersonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(name: person.name)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.title2.bold())
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let workingOn = person.workingOn, !workingOn.isEmpty {
                field("Working on", workingOn)
            }

            if !person.hereFor.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Here for").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ChipRow(items: person.hereFor.map { HereFor(rawValue: $0)?.label ?? $0 }, tint: .orange, limit: 4)
                }
            }

            if !person.sharedTopics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You both work on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ChipRow(items: person.sharedTopics, tint: .accentColor, limit: 5)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                Text(person.reason)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if person.sharedTalksCount > 0 {
                Label(
                    "\(person.sharedTalksCount) talk\(person.sharedTalksCount == 1 ? "" : "s") you both saved",
                    systemImage: "rectangle.stack.badge.checkmark"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            }

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
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
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

/// Initials circle. No photos in the app — nobody uploads one in a 60-second onboarding.
struct Avatar: View {
    let name: String
    var size: CGFloat = 52

    var body: some View {
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
