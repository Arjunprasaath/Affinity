// TalkCardView.swift — one talk as a swipe card. Owner: Teammate C.

import SwiftUI

struct TalkCardView: View {
    let talk: TalkCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text(talk.title)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if !talk.speakers.isEmpty {
                Label(talk.speakers.joined(separator: ", "), systemImage: "person.wave.2")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let abstract = talk.abstract, !abstract.isEmpty {
                Text(abstract)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(.top, 4)
            }

            if let topics = talk.topics, !topics.isEmpty {
                ChipRow(items: topics, limit: 5, colorful: true)
            }

            Spacer(minLength: 0)

            if let reason = talk.reason, !reason.isEmpty {
                reasonBox(reason)
            }

            if let clash = talk.clashesWith {
                Label("Clashes with \(clash.title)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .deckCard()
        .accessibilityLabel(accessibilityDescription)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(ConferenceTime.dayAndTime(talk.start), systemImage: "clock")
            Text("·")
            Label(talk.room, systemImage: "mappin.and.ellipse")
            Spacer()
            if let level = talk.level {
                Chip(text: level.capitalized, tint: levelColor(level))
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    /// The one line that explains why this card is in *your* deck. The whole pitch rests on it.
    private func reasonBox(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
            Text(reason)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.tint)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "beginner": .green
        case "advanced": .purple
        default: .blue
        }
    }

    private var accessibilityDescription: String {
        var parts = [talk.title]
        if !talk.speakers.isEmpty { parts.append("by \(talk.speakers.joined(separator: ", "))") }
        parts.append("\(ConferenceTime.dayAndTime(talk.start)) to \(ConferenceTime.time(talk.end))")
        parts.append("in \(talk.room)")
        if let level = talk.level { parts.append("\(level) level") }
        if let reason = talk.reason { parts.append("Recommended because \(reason)") }
        if let clash = talk.clashesWith { parts.append("Warning: clashes with \(clash.title)") }
        return parts.joined(separator: ". ")
    }
}
