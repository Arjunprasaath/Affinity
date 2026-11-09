// SwipeDeck.swift — the reusable card stack behind both the talks deck and the people deck.
// Owner: Teammate C.
//
// Right = save · Up = must-attend / strong yes · Left = skip.
// Every gesture also has a button, because dragging is not an accessible-only input
// (Merge Forward track) and because buttons are far easier to drive on stage.
//
//   SwipeDeck(items: talks, labels: .talks, onSwipe: { card, dir in ... }) { talk in
//       TalkCardView(talk: talk)
//   }

import SwiftUI
import UIKit

/// Button captions differ between the two decks, so they're passed in.
struct SwipeDeckLabels {
    var left: String
    var right: String
    var up: String?
    var leftIcon: String
    var rightIcon: String
    var upIcon: String

    static let talks = SwipeDeckLabels(
        left: "Skip", right: "Save", up: "Must attend",
        leftIcon: "xmark", rightIcon: "checkmark", upIcon: "star.fill"
    )

    static let people = SwipeDeckLabels(
        left: "Skip", right: "Want to meet", up: nil,
        leftIcon: "xmark", rightIcon: "hand.wave.fill", upIcon: "star.fill"
    )
}

struct SwipeDeck<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var labels: SwipeDeckLabels = .talks
    /// Called once per decision, in the order the user made them.
    let onSwipe: (Item, SwipeDirection) -> Void
    @ViewBuilder let card: (Item) -> Card

    /// How far a drag has to travel before it counts.
    private let horizontalThreshold: CGFloat = 110
    private let verticalThreshold: CGFloat = 130

    @State private var drag: CGSize = .zero
    @State private var leaving: SwipeDirection?
    @State private var accessibilityHint: String = ""

    private var top: Item? { items.first }
    private var behind: [Item] { Array(items.dropFirst().prefix(2)) }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Cards behind the top one, scaled back so the stack reads as a deck.
                ForEach(Array(behind.enumerated()).reversed(), id: \.element.id) { index, item in
                    card(item)
                        .scaleEffect(1 - CGFloat(index + 1) * 0.04)
                        .offset(y: CGFloat(index + 1) * 10)
                        .opacity(1 - Double(index + 1) * 0.25)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let top {
                    card(top)
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width / 22)), anchor: .bottom)
                        .overlay(alignment: .top) { verdictStamp }
                        .gesture(dragGesture)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: drag)
                        .id(top.id)
                        .transition(.identity)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Use the buttons below to decide. \(accessibilityHint)")
                }
            }
            .frame(maxHeight: .infinity)

            buttons
        }
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in drag = value.translation }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if labels.up != nil, dy < -verticalThreshold, abs(dx) < horizontalThreshold {
                    complete(.up)
                } else if dx > horizontalThreshold {
                    complete(.right)
                } else if dx < -horizontalThreshold {
                    complete(.left)
                } else {
                    drag = .zero
                }
            }
    }

    /// Fling the card off screen, then hand the decision up. The parent removes the item,
    /// which is what actually reveals the next card.
    private func complete(_ direction: SwipeDirection) {
        guard let item = top else { return }
        leaving = direction
        withAnimation(.easeOut(duration: 0.22)) {
            switch direction {
            case .right: drag = CGSize(width: 650, height: -40)
            case .left: drag = CGSize(width: -650, height: -40)
            case .up: drag = CGSize(width: 0, height: -900)
            }
        }
        accessibilityHint = "\(label(for: direction)) applied."
        UIAccessibility.post(notification: .announcement, argument: label(for: direction))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onSwipe(item, direction)
            drag = .zero
            leaving = nil
        }
    }

    private func label(for direction: SwipeDirection) -> String {
        switch direction {
        case .right: labels.right
        case .left: labels.left
        case .up: labels.up ?? labels.right
        }
    }

    // MARK: - Pieces

    /// The green SAVE / red SKIP / blue MUST watermark that tracks the drag.
    @ViewBuilder
    private var verdictStamp: some View {
        let intent: SwipeDirection? = {
            if labels.up != nil, drag.height < -70, abs(drag.width) < 70 { return .up }
            if drag.width > 50 { return .right }
            if drag.width < -50 { return .left }
            return leaving
        }()

        if let intent {
            Text(label(for: intent).uppercased())
                .font(.title3.weight(.heavy))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(color(for: intent))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color(for: intent), lineWidth: 3)
                )
                .rotationEffect(.degrees(intent == .up ? 0 : (intent == .right ? -12 : 12)))
                .padding(.top, 26)
                .opacity(min(1, Double(max(abs(drag.width), abs(drag.height)) / 110)))
                .accessibilityHidden(true)
        }
    }

    private func color(for direction: SwipeDirection) -> Color {
        switch direction {
        case .right: .green
        case .left: .red
        case .up: .blue
        }
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            deckButton(.left, tint: .red, prominent: false)
            if labels.up != nil {
                deckButton(.up, tint: .blue, prominent: false)
            }
            deckButton(.right, tint: .green, prominent: true)
        }
        .disabled(top == nil)
        .padding(.horizontal, 4)
    }

    private func deckButton(_ direction: SwipeDirection, tint: Color, prominent: Bool) -> some View {
        Button {
            complete(direction)
        } label: {
            Label(label(for: direction), systemImage: icon(for: direction))
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: prominent ? 76 : 60, height: prominent ? 76 : 60)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .clipShape(Circle())
        .accessibilityLabel(label(for: direction))
    }

    private func icon(for direction: SwipeDirection) -> String {
        switch direction {
        case .right: labels.rightIcon
        case .left: labels.leftIcon
        case .up: labels.upIcon
        }
    }
}

// MARK: - Shared chrome

/// The rounded card body both decks sit in.
struct DeckCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            )
    }
}

extension View {
    func deckCard() -> some View { modifier(DeckCardBackground()) }
}

/// Small rounded chip used for topics and "here for" values.
struct Chip: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Wraps chips onto as many lines as they need.
struct ChipRow: View {
    let items: [String]
    var tint: Color = .accentColor
    var limit: Int = 6
    /// Give each chip its own colour from the topic name (same topic, same colour everywhere).
    var colorful = false

    private func color(_ text: String) -> Color { colorful ? Theme.color(for: text) : tint }

    var body: some View {
        let shown = Array(items.prefix(limit))
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(shown, id: \.self) { Chip(text: $0, tint: color($0)) } }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { ForEach(shown.prefix(3), id: \.self) { Chip(text: $0, tint: color($0)) } }
                if shown.count > 3 {
                    HStack(spacing: 6) { ForEach(shown.dropFirst(3), id: \.self) { Chip(text: $0, tint: color($0)) } }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.joined(separator: ", "))
    }
}
