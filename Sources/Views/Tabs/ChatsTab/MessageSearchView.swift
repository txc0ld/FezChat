import SwiftUI
import SwiftData

// MARK: - MessageSearchResult

/// Lightweight value type representing a search hit across channels.
private struct MessageSearchResult: Identifiable {
    let id: UUID
    let messageID: UUID
    let channelID: UUID
    let channelName: String
    let senderName: String?
    let messageText: String
    let timestamp: Date

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: timestamp)
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: timestamp)
        }
    }
}

// MARK: - MessageSearchView

/// Full-screen sheet for searching message content across all channels.
/// Queries SwiftData for text messages and filters in-memory by payload content.
struct MessageSearchView: View {

    @State private var searchText = ""
    @State private var searchResults: [MessageSearchResult] = []
    @State private var isSearching = false
    @FocusState private var isFieldFocused: Bool

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Debounce task handle
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, BlipSpacing.md)
                        .padding(.top, BlipSpacing.sm)
                        .padding(.bottom, BlipSpacing.md)

                    contentArea
                }
            }
            .navigationTitle("Search Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.blipAccentPurple)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onChange(of: searchText) { _, newValue in
            debounceSearch(query: newValue)
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: BlipSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFieldFocused ? Color.blipAccentPurple : theme.colors.mutedText)

            TextField("Search messages...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.custom(BlipFontName.regular, size: 16, relativeTo: .body))
                .foregroundStyle(theme.colors.text)
                .focused($isFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, BlipSpacing.md)
        .padding(.vertical, BlipSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: BlipCornerRadius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BlipCornerRadius.lg, style: .continuous)
                .stroke(
                    isFieldFocused
                        ? Color.blipAccentPurple.opacity(0.5)
                        : Color.clear,
                    lineWidth: BlipSizing.hairline
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFieldFocused)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyPromptState
        } else if isSearching {
            searchingState
        } else if searchResults.isEmpty {
            noResultsState
        } else {
            resultsList
        }
    }

    // MARK: - Empty Prompt (before searching)

    private var emptyPromptState: some View {
        VStack(spacing: BlipSpacing.lg) {
            Spacer()

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.mutedText.opacity(0.5))

            Text("Search across all channels")
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.text)

            Text("Find messages by content from\nany conversation.")
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.mutedText)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .staggeredReveal(index: 0)
    }

    // MARK: - Searching (spinner)

    private var searchingState: some View {
        VStack(spacing: BlipSpacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.blipAccentPurple)

            Text("Searching...")
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.mutedText)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results

    private var noResultsState: some View {
        VStack(spacing: BlipSpacing.lg) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.mutedText.opacity(0.5))

            Text("No results for \"\(searchText)\"")
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.text)

            Text("Try a different search term.")
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.mutedText)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .staggeredReveal(index: 0)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: BlipSpacing.sm) {
                // Result count header
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                    Spacer()
                }
                .padding(.horizontal, BlipSpacing.xs)

                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                    resultRow(for: result)
                        .staggeredReveal(index: index)
                }
            }
            .padding(.horizontal, BlipSpacing.md)
            .padding(.bottom, BlipSpacing.xl)
        }
    }

    // MARK: - Result Row

    private func resultRow(for result: MessageSearchResult) -> some View {
        GlassCard(
            thickness: .ultraThin,
            cornerRadius: BlipCornerRadius.xl,
            padding: .blipContent
        ) {
            VStack(alignment: .leading, spacing: BlipSpacing.sm) {
                // Channel name + timestamp
                HStack {
                    Text(result.channelName)
                        .font(.custom(BlipFontName.semiBold, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.blipAccentPurple)

                    Spacer()

                    Text(result.formattedDate)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.tertiaryText)
                }

                // Sender name
                if let senderName = result.senderName {
                    Text(senderName)
                        .font(.custom(BlipFontName.bold, size: 15, relativeTo: .body))
                        .foregroundStyle(theme.colors.text)
                }

                // Message text with highlighted match
                highlightedText(result.messageText, query: searchText)
                    .font(.custom(BlipFontName.regular, size: 14, relativeTo: .body))
                    .foregroundStyle(theme.colors.mutedText)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Highlighted Text

    /// Builds concatenated `Text` views that bold the matching substring in accent purple.
    private func highlightedText(_ text: String, query: String) -> Text {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else {
            return Text(text)
        }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = trimmedQuery.lowercased()

        guard let range = lowercasedText.range(of: lowercasedQuery) else {
            return Text(text)
        }

        let beforeMatch = String(text[text.startIndex..<range.lowerBound])
        let matchText = String(text[range.lowerBound..<range.upperBound])
        let afterMatch = String(text[range.upperBound..<text.endIndex])

        return Text(beforeMatch)
            + Text(matchText)
                .font(.custom(BlipFontName.bold, size: 14, relativeTo: .body))
                .foregroundColor(Color.blipAccentPurple)
            + Text(afterMatch)
    }

    // MARK: - Search Logic

    private func debounceSearch(query: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true

        let predicate = #Predicate<Message> { message in
            message.typeRaw == "text"
        }
        var descriptor = FetchDescriptor<Message>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        descriptor.fetchLimit = 100

        do {
            let messages = try modelContext.fetch(descriptor)
            searchResults = messages.compactMap { message in
                guard let text = String(data: message.encryptedPayload, encoding: .utf8),
                      text.localizedCaseInsensitiveContains(query) else { return nil }
                return MessageSearchResult(
                    id: message.id,
                    messageID: message.id,
                    channelID: message.channel?.id ?? UUID(),
                    channelName: message.channel?.name ?? "Chat",
                    senderName: message.sender?.resolvedDisplayName ?? message.sender?.username,
                    messageText: text,
                    timestamp: message.createdAt
                )
            }
        } catch {
            searchResults = []
        }
        isSearching = false
    }
}

// MARK: - Previews

#Preview("Message Search — Empty") {
    MessageSearchView()
        .environment(\.theme, Theme.shared)
        .preferredColorScheme(.dark)
}

#Preview("Message Search — Light") {
    MessageSearchView()
        .environment(\.theme, Theme.resolved(for: .light))
        .preferredColorScheme(.light)
}
