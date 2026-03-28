import SwiftUI

// MARK: - LostAndFoundView

/// Simple chat view for the festival's lost & found public channel.
///
/// Displays messages in a scrollable list with a text input at the bottom.
/// Messages are public and not encrypted.
struct LostAndFoundView: View {

    @State private var messages: [LostFoundMessage] = LostAndFoundView.sampleMessages
    @State private var inputText: String = ""
    @State private var scrollToBottom = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBanner
            messageList
            inputBar
        }
        .background(
            colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.3)
        )
    }

    // MARK: - Header

    private var headerBanner: some View {
        HStack(spacing: FCSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.fcAccentPurple)

            Text("Lost & Found")
                .font(theme.typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.text)

            Spacer()

            Text("Public channel")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.mutedText)
                .padding(.horizontal, FCSpacing.sm)
                .padding(.vertical, FCSpacing.xs)
                .background(Capsule().fill(theme.colors.hover))
        }
        .padding(.horizontal, FCSpacing.md)
        .padding(.vertical, FCSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: FCSpacing.sm) {
                    ForEach(messages) { message in
                        LostFoundMessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(FCSpacing.md)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastID = messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: FCSpacing.sm) {
            TextField("Describe lost/found item...", text: $inputText, axis: .vertical)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.text)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(FCSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: FCCornerRadius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FCCornerRadius.lg, style: .continuous)
                        .stroke(
                            colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08),
                            lineWidth: FCSizing.hairline
                        )
                )
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .accessibilityLabel("Message input for lost and found")

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? theme.colors.mutedText
                                    : .fcAccentPurple)
            }
            .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, FCSpacing.md)
        .padding(.vertical, FCSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newMessage = LostFoundMessage(
            id: UUID(),
            senderName: "You",
            senderInitials: "YO",
            text: trimmed,
            timestamp: Date(),
            isOwn: true
        )
        messages.append(newMessage)
        inputText = ""
    }
}

// MARK: - LostFoundMessageBubble

/// A single message in the lost & found channel.
private struct LostFoundMessageBubble: View {

    let message: LostFoundMessage

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: FCSpacing.sm) {
            if !message.isOwn {
                // Sender avatar
                Circle()
                    .fill(LinearGradient.fcAccent.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(message.senderInitials)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: FCSpacing.xs) {
                if !message.isOwn {
                    Text(message.senderName)
                        .font(theme.typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.fcAccentPurple)
                }

                Text(message.text)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.text)
                    .padding(FCSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: FCCornerRadius.lg, style: .continuous)
                            .fill(message.isOwn
                                  ? .fcAccentPurple.opacity(0.15)
                                  : (colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.04)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FCCornerRadius.lg, style: .continuous)
                            .stroke(
                                colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06),
                                lineWidth: FCSizing.hairline
                            )
                    )

                Text(message.timestamp, style: .time)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.mutedText.opacity(0.6))
            }

            if message.isOwn {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.senderName): \(message.text)")
    }
}

// MARK: - Data Model

struct LostFoundMessage: Identifiable {
    let id: UUID
    let senderName: String
    let senderInitials: String
    let text: String
    let timestamp: Date
    let isOwn: Bool
}

// MARK: - Sample Data

extension LostAndFoundView {
    static let sampleMessages: [LostFoundMessage] = [
        LostFoundMessage(id: UUID(), senderName: "Alex K", senderInitials: "AK", text: "Lost a green backpack near the West Holts stage around 6pm. Has stickers on it. Please DM if found!", timestamp: Date().addingTimeInterval(-3600), isOwn: false),
        LostFoundMessage(id: UUID(), senderName: "Jordan", senderInitials: "JO", text: "Found a set of car keys near Camping B showers. Red Toyota keychain. At the info tent.", timestamp: Date().addingTimeInterval(-1800), isOwn: false),
        LostFoundMessage(id: UUID(), senderName: "You", senderInitials: "YO", text: "Has anyone found a phone with a purple case? Dropped it somewhere around the food trucks.", timestamp: Date().addingTimeInterval(-600), isOwn: true),
    ]
}

// MARK: - Preview

#Preview("Lost & Found") {
    ZStack {
        GradientBackground()
        LostAndFoundView()
    }
    .frame(height: 500)
    .preferredColorScheme(.dark)
    .festiChatTheme()
}
