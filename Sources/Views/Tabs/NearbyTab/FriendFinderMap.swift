import SwiftUI
import MapKit

// MARK: - FriendFinderMap

/// MapKit view showing friend locations on the festival map.
///
/// Features:
/// - Colored pins per friend with precision indicators (solid pin vs fuzzy circle)
/// - "I'm here" beacon drop
/// - Navigate button for walking directions
/// - Breadcrumb trails (opt-in)
///
/// All interactive elements have 44pt minimum tap targets and VoiceOver support.
struct FriendFinderMap: View {

    let friends: [FriendMapPin]
    let userLocation: CLLocationCoordinate2D?
    let beacons: [BeaconPin]

    var onDropBeacon: ((CLLocationCoordinate2D) -> Void)?
    var onNavigateToFriend: ((FriendMapPin) -> Void)?
    var onFriendTap: ((FriendMapPin) -> Void)?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedFriend: FriendMapPin?
    @State private var showBeaconConfirm = false

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mapContent

            // Controls overlay
            VStack(spacing: FCSpacing.sm) {
                recenterButton
                dropBeaconButton
            }
            .padding(FCSpacing.md)
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        Map(position: $cameraPosition, selection: $selectedFriend) {
            // User location
            if let userLocation {
                Annotation("You", coordinate: userLocation) {
                    ZStack {
                        Circle()
                            .fill(.fcAccentPurple.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Circle()
                            .fill(.fcAccentPurple)
                            .frame(width: 14, height: 14)

                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                    .accessibilityLabel("Your location")
                }
            }

            // Friend pins
            ForEach(friends) { friend in
                Annotation(friend.displayName, coordinate: friend.coordinate) {
                    FriendPinView(
                        friend: friend,
                        isSelected: selectedFriend?.id == friend.id,
                        onTap: {
                            selectedFriend = friend
                            onFriendTap?(friend)
                        }
                    )
                }
                .tag(friend)
            }

            // Beacon pins
            ForEach(beacons) { beacon in
                Annotation(beacon.label, coordinate: beacon.coordinate) {
                    BeaconPinView(beacon: beacon)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .clipShape(RoundedRectangle(cornerRadius: FCCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FCCornerRadius.xl, style: .continuous)
                .stroke(
                    colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08),
                    lineWidth: FCSizing.hairline
                )
        )
        .overlay(alignment: .bottom) {
            if let selected = selectedFriend {
                friendDetailCard(for: selected)
                    .padding(FCSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(SpringConstants.accessiblePageEntrance, value: selectedFriend?.id)
    }

    // MARK: - Friend Detail Card

    @ViewBuilder
    private func friendDetailCard(for friend: FriendMapPin) -> some View {
        GlassCard(thickness: .thick, cornerRadius: FCCornerRadius.xl) {
            HStack(spacing: FCSpacing.md) {
                // Avatar
                Circle()
                    .fill(friend.color)
                    .frame(width: FCSizing.avatarSmall, height: FCSizing.avatarSmall)
                    .overlay(
                        Text(String(friend.displayName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: FCSpacing.xs) {
                    Text(friend.displayName)
                        .font(theme.typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.text)

                    Text(friend.precisionDescription)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.mutedText)
                }

                Spacer()

                // Navigate button
                Button(action: { onNavigateToFriend?(friend) }) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: FCSizing.minTapTarget, height: FCSizing.minTapTarget)
                        .background(
                            Circle()
                                .fill(LinearGradient.fcAccent)
                        )
                }
                .accessibilityLabel("Navigate to \(friend.displayName)")

                // Dismiss
                Button(action: { selectedFriend = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.colors.mutedText)
                        .frame(width: FCSizing.minTapTarget, height: FCSizing.minTapTarget)
                }
                .accessibilityLabel("Close")
            }
        }
    }

    // MARK: - Controls

    private var recenterButton: some View {
        Button(action: {
            withAnimation {
                cameraPosition = .automatic
            }
        }) {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.fcAccentPurple)
                .frame(width: FCSizing.minTapTarget, height: FCSizing.minTapTarget)
                .background(
                    Circle()
                        .fill(.thickMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    colorScheme == .dark ? .white.opacity(0.15) : .black.opacity(0.1),
                                    lineWidth: FCSizing.hairline
                                )
                        )
                )
        }
        .accessibilityLabel("Recenter map")
    }

    private var dropBeaconButton: some View {
        Button(action: { showBeaconConfirm = true }) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: FCSizing.minTapTarget, height: FCSizing.minTapTarget)
                .background(
                    Circle()
                        .fill(LinearGradient.fcAccent)
                )
        }
        .accessibilityLabel("Drop I'm Here beacon")
        .alert("Drop Beacon", isPresented: $showBeaconConfirm) {
            Button("Drop Here") {
                if let userLocation {
                    onDropBeacon?(userLocation)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your current location as a beacon. It will expire in 30 minutes.")
        }
    }
}

// MARK: - FriendPinView

/// A single friend pin on the map with precision-appropriate visual.
private struct FriendPinView: View {

    let friend: FriendMapPin
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                switch friend.precision {
                case .precise:
                    // Solid pin
                    Circle()
                        .fill(friend.color)
                        .frame(width: isSelected ? 20 : 14, height: isSelected ? 20 : 14)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        )
                        .shadow(color: friend.color.opacity(0.5), radius: 4)

                case .fuzzy:
                    // Fuzzy circle indicating area
                    Circle()
                        .fill(friend.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(friend.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        )
                        .overlay(
                            Circle()
                                .fill(friend.color)
                                .frame(width: 8, height: 8)
                        )

                case .off:
                    // Hidden, show generic marker
                    Circle()
                        .fill(friend.color.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(friend.displayName), \(friend.precisionDescription)")
    }
}

// MARK: - BeaconPinView

/// A beacon pin dropped by a friend or the user.
private struct BeaconPinView: View {

    let beacon: BeaconPin

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Pulse ring
            if !SpringConstants.isReduceMotionEnabled {
                Circle()
                    .stroke(.fcAccentPurple.opacity(0.3), lineWidth: 1)
                    .frame(width: 36, height: 36)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
            }

            // Pin
            VStack(spacing: 0) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.fcAccentPurple)

                Text(beacon.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(.fcAccentPurple)
                    )
            }
        }
        .onAppear {
            guard !SpringConstants.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .accessibilityLabel("Beacon: \(beacon.label)")
    }
}

// MARK: - Data Models

/// View-level data for a friend's location on the map.
struct FriendMapPin: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let coordinate: CLLocationCoordinate2D
    let precision: LocationPinPrecision
    let color: Color
    let lastUpdated: Date

    var precisionDescription: String {
        switch precision {
        case .precise: return "Precise location"
        case .fuzzy: return "Approximate area"
        case .off: return "Location hidden"
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FriendMapPin, rhs: FriendMapPin) -> Bool {
        lhs.id == rhs.id
    }
}

enum LocationPinPrecision: String {
    case precise
    case fuzzy
    case off
}

/// View-level data for a beacon pin.
struct BeaconPin: Identifiable {
    let id: UUID
    let label: String
    let coordinate: CLLocationCoordinate2D
    let createdBy: String
    let expiresAt: Date
}

// MARK: - Preview

#Preview("Friend Finder Map") {
    let friends: [FriendMapPin] = [
        FriendMapPin(
            id: UUID(),
            displayName: "Sarah",
            coordinate: CLLocationCoordinate2D(latitude: 51.0048, longitude: -2.5862),
            precision: .precise,
            color: .blue,
            lastUpdated: Date()
        ),
        FriendMapPin(
            id: UUID(),
            displayName: "Jake",
            coordinate: CLLocationCoordinate2D(latitude: 51.0052, longitude: -2.5850),
            precision: .fuzzy,
            color: .green,
            lastUpdated: Date().addingTimeInterval(-60)
        ),
    ]

    let beacons: [BeaconPin] = [
        BeaconPin(
            id: UUID(),
            label: "Meet here!",
            coordinate: CLLocationCoordinate2D(latitude: 51.0045, longitude: -2.5858),
            createdBy: "You",
            expiresAt: Date().addingTimeInterval(1800)
        ),
    ]

    FriendFinderMap(
        friends: friends,
        userLocation: CLLocationCoordinate2D(latitude: 51.0043, longitude: -2.5856),
        beacons: beacons
    )
    .frame(height: 400)
    .padding()
    .background(GradientBackground())
    .preferredColorScheme(.dark)
}
