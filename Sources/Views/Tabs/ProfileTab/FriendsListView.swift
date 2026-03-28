import SwiftUI

// MARK: - FriendsListView

/// Friends management view with Online/All/Pending/Blocked sections,
/// search, and add-by-username functionality.
struct FriendsListView: View {

    @State private var friends: [FriendListItem] = FriendsListView.sampleFriends
    @State private var searchText: String = ""
    @State private var selectedSection: FriendSection = .all
    @State private var showAddFriend = false
    @State private var addUsername: String = ""
    @State private var selectedFriend: FriendListItem?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                searchBar
                sectionPicker
                friendsList
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddFriend = true }) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.fcAccentPurple)
                }
                .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
                .accessibilityLabel("Add friend")
            }
        }
        .alert("Add Friend", isPresented: $showAddFriend) {
            TextField("Username", text: $addUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Send Request") {
                sendFriendRequest()
            }
            Button("Cancel", role: .cancel) {
                addUsername = ""
            }
        } message: {
            Text("Enter their username to send a friend request.")
        }
        .sheet(item: $selectedFriend) { friend in
            ProfileSheet(
                isPresented: Binding(
                    get: { selectedFriend != nil },
                    set: { if !$0 { selectedFriend = nil } }
                ),
                displayName: friend.displayName,
                username: friend.username,
                bio: friend.bio,
                isFriend: friend.status == .accepted,
                isOnline: friend.isOnline
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: FCSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.mutedText)

            TextField("Search friends...", text: $searchText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.text)
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.mutedText)
                }
                .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
            }
        }
        .padding(.horizontal, FCSpacing.md)
        .padding(.vertical, FCSpacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: FCCornerRadius.lg, style: .continuous))
        .padding(.horizontal, FCSpacing.md)
        .padding(.vertical, FCSpacing.sm)
        .accessibilityLabel("Search friends")
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FCSpacing.sm) {
                ForEach(FriendSection.allCases, id: \.self) { section in
                    sectionChip(section)
                }
            }
            .padding(.horizontal, FCSpacing.md)
            .padding(.bottom, FCSpacing.sm)
        }
    }

    private func sectionChip(_ section: FriendSection) -> some View {
        let count = friendsForSection(section).count
        return Button(action: {
            withAnimation(SpringConstants.accessiblePageEntrance) {
                selectedSection = section
            }
        }) {
            HStack(spacing: FCSpacing.xs) {
                Text(section.displayName)
                    .font(theme.typography.caption)
                    .fontWeight(selectedSection == section ? .semibold : .regular)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selectedSection == section ? .white : theme.colors.mutedText)
                }
            }
            .foregroundStyle(selectedSection == section ? .white : theme.colors.text)
            .padding(.horizontal, FCSpacing.md)
            .padding(.vertical, FCSpacing.sm)
            .background(
                Capsule()
                    .fill(selectedSection == section
                          ? AnyShapeStyle(LinearGradient.fcAccent)
                          : AnyShapeStyle(theme.colors.hover))
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: FCSizing.minTapTarget)
        .accessibilityLabel("\(section.displayName), \(count) friends")
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    // MARK: - Friends List

    private var friendsList: some View {
        ScrollView {
            let filteredFriends = friendsForSection(selectedSection)
                .filter { friend in
                    searchText.isEmpty ||
                    friend.displayName.localizedCaseInsensitiveContains(searchText) ||
                    friend.username.localizedCaseInsensitiveContains(searchText)
                }

            if filteredFriends.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: FCSpacing.sm) {
                    ForEach(Array(filteredFriends.enumerated()), id: \.element.id) { index, friend in
                        FriendRow(friend: friend, onTap: { selectedFriend = friend })
                            .staggeredReveal(index: index)
                    }
                }
                .padding(.horizontal, FCSpacing.md)
                .padding(.bottom, FCSpacing.xxl)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: FCSpacing.md) {
            Spacer().frame(height: FCSpacing.xxl)

            Image(systemName: selectedSection.emptyIcon)
                .font(.system(size: 40))
                .foregroundStyle(theme.colors.mutedText)

            Text(selectedSection.emptyMessage)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.mutedText)
                .multilineTextAlignment(.center)

            if selectedSection == .all && searchText.isEmpty {
                GlassButton("Add Friend", icon: "person.badge.plus", style: .secondary, size: .small) {
                    showAddFriend = true
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func friendsForSection(_ section: FriendSection) -> [FriendListItem] {
        switch section {
        case .online: return friends.filter { $0.isOnline && $0.status == .accepted }
        case .all: return friends.filter { $0.status == .accepted }
        case .pending: return friends.filter { $0.status == .pending }
        case .blocked: return friends.filter { $0.status == .blocked }
        }
    }

    private func sendFriendRequest() {
        guard !addUsername.isEmpty else { return }
        // In production: send via mesh
        addUsername = ""
    }
}

// MARK: - FriendRow

private struct FriendRow: View {

    let friend: FriendListItem
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FCSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient.fcAccent.opacity(0.7))
                        .frame(width: FCSizing.avatarSmall, height: FCSizing.avatarSmall)
                        .overlay(
                            Text(String(friend.displayName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    if friend.isOnline {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .offset(x: 14, y: 14)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: FCSpacing.xs) {
                    HStack {
                        Text(friend.displayName)
                            .font(theme.typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.colors.text)

                        if friend.isPhoneVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.fcAccentPurple)
                        }
                    }

                    Text("@\(friend.username)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                }

                Spacer()

                // Status indicator
                if friend.status == .pending {
                    Text("Pending")
                        .font(theme.typography.caption)
                        .foregroundStyle(FCColors.darkColors.statusAmber)
                        .padding(.horizontal, FCSpacing.sm)
                        .padding(.vertical, FCSpacing.xs)
                        .background(Capsule().fill(FCColors.darkColors.statusAmber.opacity(0.12)))
                } else if friend.status == .blocked {
                    Text("Blocked")
                        .font(theme.typography.caption)
                        .foregroundStyle(FCColors.darkColors.statusRed)
                        .padding(.horizontal, FCSpacing.sm)
                        .padding(.vertical, FCSpacing.xs)
                        .background(Capsule().fill(FCColors.darkColors.statusRed.opacity(0.12)))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.mutedText)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: FCSizing.minTapTarget)
        .glassCard(thickness: .ultraThin, cornerRadius: FCCornerRadius.lg, borderOpacity: 0.1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(friend.displayName), @\(friend.username)\(friend.isOnline ? ", online" : "")\(friend.status == .pending ? ", pending" : "")")
    }
}

// MARK: - Supporting Types

enum FriendSection: CaseIterable {
    case online, all, pending, blocked

    var displayName: String {
        switch self {
        case .online: return "Online"
        case .all: return "All"
        case .pending: return "Pending"
        case .blocked: return "Blocked"
        }
    }

    var emptyIcon: String {
        switch self {
        case .online: return "wifi.slash"
        case .all: return "person.2"
        case .pending: return "clock"
        case .blocked: return "hand.raised"
        }
    }

    var emptyMessage: String {
        switch self {
        case .online: return "No friends online right now"
        case .all: return "No friends yet. Add someone!"
        case .pending: return "No pending requests"
        case .blocked: return "No blocked users"
        }
    }
}

struct FriendListItem: Identifiable {
    let id: UUID
    let displayName: String
    let username: String
    let bio: String
    let isOnline: Bool
    let isPhoneVerified: Bool
    let status: FriendStatus
}

// MARK: - Sample Data

extension FriendsListView {
    static let sampleFriends: [FriendListItem] = [
        FriendListItem(id: UUID(), displayName: "Sarah Chen", username: "sarahc", bio: "Music and mountains", isOnline: true, isPhoneVerified: true, status: .accepted),
        FriendListItem(id: UUID(), displayName: "Jake Morrison", username: "jakem", bio: "Always at the front", isOnline: true, isPhoneVerified: false, status: .accepted),
        FriendListItem(id: UUID(), displayName: "Priya Patel", username: "priyap", bio: "Festival photographer", isOnline: false, isPhoneVerified: true, status: .accepted),
        FriendListItem(id: UUID(), displayName: "Tom Wilson", username: "tomw", bio: "", isOnline: false, isPhoneVerified: false, status: .pending),
        FriendListItem(id: UUID(), displayName: "Blocked User", username: "spam123", bio: "", isOnline: false, isPhoneVerified: false, status: .blocked),
    ]
}

// MARK: - Preview

#Preview("Friends List") {
    NavigationStack {
        FriendsListView()
    }
    .preferredColorScheme(.dark)
    .festiChatTheme()
}
