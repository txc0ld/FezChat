import SwiftUI

// MARK: - ChatView

/// Full chat conversation view.
/// ScrollViewReader + LazyVStack, auto-scroll on new message, date headers,
/// typing indicator, and pinned message input.
struct ChatView: View {

    let conversation: ConversationPreview

    @State private var messageText: String = ""
    @State private var messages: [ChatMessage] = ChatMessage.sampleMessages
    @State private var isTyping = false
    @State private var showImageViewer = false
    @State private var selectedImageData: Data? = nil
    @State private var showPaywall = false
    @State private var scrollToBottomID: UUID? = nil

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messagesScrollView

            // Typing indicator
            if isTyping {
                HStack {
                    TypingIndicator()
                    Spacer()
                }
                .padding(.horizontal, FCSpacing.md)
                .padding(.vertical, FCSpacing.xs)
                .transition(.opacity)
            }

            // Message input (pinned at bottom)
            MessageInput(
                text: $messageText,
                onSend: { text in
                    sendMessage(text)
                },
                onAttachment: {
                    // Attachment handling
                },
                onPTTStart: {
                    // PTT start
                },
                onPTTEnd: {
                    // PTT end
                },
                messagesRemaining: nil,
                onLowBalanceTap: {
                    showPaywall = true
                }
            )
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                navigationTitleView
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            ImageViewer(imageData: selectedImageData, isPresented: $showImageViewer)
        }
    }

    // MARK: - Navigation Title

    private var navigationTitleView: some View {
        HStack(spacing: FCSpacing.sm) {
            AvatarView(
                imageData: conversation.avatarData,
                name: conversation.displayName,
                size: 32,
                ringStyle: conversation.ringStyle,
                showOnlineIndicator: conversation.isOnline
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.displayName)
                    .font(.custom(FCFontName.semiBold, size: 16, relativeTo: .body))
                    .foregroundStyle(theme.colors.text)

                Text(conversation.isOnline ? "Online" : "Last seen recently")
                    .font(.custom(FCFontName.regular, size: 12, relativeTo: .caption2))
                    .foregroundStyle(
                        conversation.isOnline
                            ? theme.colors.statusGreen
                            : theme.colors.mutedText
                    )
            }
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: FCSpacing.sm) {
                    // Date headers + messages
                    ForEach(Array(groupedMessages.enumerated()), id: \.offset) { sectionIndex, section in
                        // Date header
                        dateHeader(for: section.date)
                            .id("header-\(sectionIndex)")

                        // Messages in this date group
                        ForEach(Array(section.messages.enumerated()), id: \.element.id) { messageIndex, message in
                            MessageBubble(
                                message: message,
                                index: messageIndex,
                                onReply: {
                                    // Reply handling
                                },
                                onImageTap: {
                                    selectedImageData = message.imageData
                                    showImageViewer = true
                                }
                            )
                            .id(message.id)
                        }
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, FCSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(SpringConstants.accessibleMessage) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Date Header

    private func dateHeader(for date: Date) -> some View {
        Text(formattedDateHeader(date))
            .font(.custom(FCFontName.medium, size: 12, relativeTo: .caption2))
            .foregroundStyle(theme.colors.mutedText)
            .padding(.horizontal, FCSpacing.md)
            .padding(.vertical, FCSpacing.xs + 2)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, FCSpacing.sm)
    }

    // MARK: - Grouped Messages

    private struct MessageSection {
        let date: Date
        let messages: [ChatMessage]
    }

    private var groupedMessages: [MessageSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return grouped
            .sorted { $0.key < $1.key }
            .map { MessageSection(date: $0.key, messages: $0.value.sorted { $0.timestamp < $1.timestamp }) }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let newMessage = ChatMessage(
            id: UUID(),
            senderName: "Me",
            senderAvatarData: nil,
            isFromMe: true,
            showSenderName: false,
            text: text,
            contentType: .text,
            deliveryStatus: .sent,
            timestamp: Date(),
            isEdited: false,
            replyPreview: nil,
            imageData: nil,
            voiceNoteDuration: nil,
            waveformSamples: []
        )
        withAnimation(SpringConstants.accessibleMessage) {
            messages.append(newMessage)
        }

        // Simulate typing indicator from other side
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { isTyping = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { isTyping = false }
            let reply = ChatMessage(
                id: UUID(),
                senderName: conversation.displayName,
                senderAvatarData: conversation.avatarData,
                isFromMe: false,
                showSenderName: false,
                text: "Got it! See you there",
                contentType: .text,
                deliveryStatus: .delivered,
                timestamp: Date(),
                isEdited: false,
                replyPreview: text,
                imageData: nil,
                voiceNoteDuration: nil,
                waveformSamples: []
            )
            withAnimation(SpringConstants.accessibleMessage) {
                messages.append(reply)
            }
        }
    }

    // MARK: - Formatting

    private func formattedDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview("Chat View") {
    NavigationStack {
        ChatView(
            conversation: ConversationPreview.sampleConversations[0]
        )
    }
    .background(GradientBackground())
    .environment(\.theme, Theme.shared)
}

#Preview("Chat View - Light") {
    NavigationStack {
        ChatView(
            conversation: ConversationPreview.sampleConversations[0]
        )
    }
    .background(Color.white)
    .environment(\.theme, Theme.resolved(for: .light))
    .preferredColorScheme(.light)
}
