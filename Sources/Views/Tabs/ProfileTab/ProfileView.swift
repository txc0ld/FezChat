import SwiftUI

// MARK: - ProfileView

/// Main profile tab showing user avatar, name, username, bio,
/// message pack balance, and quick action cards.
struct ProfileView: View {

    // In production from @Query/@EnvironmentObject
    @State private var displayName: String = "Alex Rivers"
    @State private var username: String = "alexrivers"
    @State private var bio: String = "Festival lover. Catch me at the Pyramid Stage."
    @State private var messageBalance: Int = 47
    @State private var isSubscriber: Bool = false

    @State private var showEditProfile = false
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var showMessageStore = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: FCSpacing.lg) {
                        avatarSection
                            .staggeredReveal(index: 0)

                        balanceCard
                            .staggeredReveal(index: 1)

                        quickActions
                            .staggeredReveal(index: 2)

                        Spacer().frame(height: FCSpacing.xxl)
                    }
                    .padding(.top, FCSpacing.md)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.colors.mutedText)
                    }
                    .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    isPresented: $showEditProfile,
                    displayName: displayName,
                    username: username,
                    bio: bio
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showFriends) {
                NavigationStack {
                    FriendsListView()
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showMessageStore) {
                NavigationStack {
                    MessagePackStore()
                }
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        GlassCard(thickness: .regular) {
            VStack(spacing: FCSpacing.md) {
                // Large avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient.fcAccent)
                        .frame(width: FCSizing.avatarLarge, height: FCSizing.avatarLarge)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    // Subscriber ring
                    if isSubscriber {
                        Circle()
                            .stroke(LinearGradient.fcAccent, lineWidth: 3)
                            .frame(width: FCSizing.avatarLarge + 8, height: FCSizing.avatarLarge + 8)
                    }

                    // Edit button
                    Button(action: { showEditProfile = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.fcAccentPurple)
                            .background(Circle().fill(colorScheme == .dark ? .black : .white).frame(width: 22, height: 22))
                    }
                    .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
                    .offset(x: 28, y: 28)
                    .accessibilityLabel("Edit profile picture")
                }

                // Name and username
                VStack(spacing: FCSpacing.xs) {
                    Text(displayName)
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.text)

                    Text("@\(username)")
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.mutedText)
                }

                // Bio
                if !bio.isEmpty {
                    Text(bio)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.mutedText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                // Edit profile button
                GlassButton("Edit Profile", icon: "pencil", style: .secondary, size: .small) {
                    showEditProfile = true
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, FCSpacing.md)
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        Button(action: { showMessageStore = true }) {
            GlassCard(thickness: .regular) {
                HStack(spacing: FCSpacing.md) {
                    VStack(alignment: .leading, spacing: FCSpacing.xs) {
                        Text("Message Balance")
                            .font(theme.typography.secondary)
                            .foregroundStyle(theme.colors.mutedText)

                        HStack(alignment: .firstTextBaseline, spacing: FCSpacing.xs) {
                            Text("\(messageBalance)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.fcAccentPurple)
                                .contentTransition(.numericText())

                            Text("messages left")
                                .font(theme.typography.secondary)
                                .foregroundStyle(theme.colors.mutedText)
                        }
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.fcAccentPurple)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, FCSpacing.md)
        .accessibilityLabel("Message balance: \(messageBalance) messages left. Tap to buy more.")
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: FCSpacing.md) {
            HStack(spacing: FCSpacing.md) {
                quickActionCard(icon: "person.2.fill", title: "Friends", subtitle: "12 friends") {
                    showFriends = true
                }

                quickActionCard(icon: "gearshape.fill", title: "Settings", subtitle: "Preferences") {
                    showSettings = true
                }
            }

            HStack(spacing: FCSpacing.md) {
                quickActionCard(icon: "bag.fill", title: "Message Packs", subtitle: "\(messageBalance) left") {
                    showMessageStore = true
                }

                quickActionCard(icon: "qrcode", title: "My QR Code", subtitle: "Share profile") {
                    // Share QR code
                }
            }
        }
        .padding(.horizontal, FCSpacing.md)
    }

    private func quickActionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassCard(thickness: .regular, cornerRadius: FCCornerRadius.xl) {
                VStack(alignment: .leading, spacing: FCSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.fcAccentPurple)

                    Text(title)
                        .font(theme.typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.text)

                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: FCSizing.minTapTarget)
        .accessibilityLabel("\(title): \(subtitle)")
    }
}

// MARK: - Preview

#Preview("Profile Tab") {
    ProfileView()
        .preferredColorScheme(.dark)
        .festiChatTheme()
}

#Preview("Profile Tab - Light") {
    ProfileView()
        .preferredColorScheme(.light)
        .festiChatTheme()
}
