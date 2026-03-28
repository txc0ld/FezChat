import SwiftUI

// MARK: - CreateProfileStep

/// Onboarding step 2: Username, phone OTP verification, optional avatar picker.
/// Single glass card layout.
struct CreateProfileStep: View {

    /// Called when the user completes profile creation.
    var onComplete: () -> Void = {}

    @State private var username: String = ""
    @State private var phoneNumber: String = ""
    @State private var otpCode: String = ""
    @State private var showOTPField = false
    @State private var isVerifyingPhone = false
    @State private var isVerified = false
    @State private var showAvatarPicker = false
    @State private var selectedAvatarImage: UIImage? = nil
    @State private var usernameError: String? = nil
    @State private var contentVisible = false
    @FocusState private var focusedField: Field?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private enum Field: Hashable {
        case username
        case phone
        case otp
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FCSpacing.lg) {
                // Title
                VStack(spacing: FCSpacing.sm) {
                    Text("Create your profile")
                        .font(theme.typography.largeTitle)
                        .foregroundStyle(theme.colors.text)

                    Text("Pick a username and verify your phone number.")
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.mutedText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, FCSpacing.xl)

                // Avatar picker
                avatarSection

                // Form card
                GlassCard(thickness: .regular) {
                    VStack(spacing: FCSpacing.md) {
                        // Username field
                        usernameField

                        Divider()
                            .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))

                        // Phone field
                        phoneField

                        // OTP field (conditional)
                        if showOTPField {
                            Divider()
                                .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                            otpField
                        }
                    }
                }
                .padding(.horizontal, FCSpacing.md)

                // Continue button
                GlassButton(
                    "Continue",
                    icon: isVerified ? "checkmark" : "arrow.right",
                    isLoading: isVerifyingPhone
                ) {
                    if isFormValid {
                        onComplete()
                    }
                }
                .fullWidth()
                .disabled(!isFormValid)
                .padding(.horizontal, FCSpacing.lg)
                .padding(.bottom, FCSpacing.xl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(contentVisible ? 1.0 : 0.0)
        .offset(y: contentVisible ? 0 : 15)
        .onAppear {
            withAnimation(SpringConstants.accessiblePageEntrance) {
                contentVisible = true
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        Button {
            showAvatarPicker = true
        } label: {
            ZStack {
                if let image = selectedAvatarImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: FCSizing.avatarLarge, height: FCSizing.avatarLarge)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: FCSizing.avatarLarge, height: FCSizing.avatarLarge)
                        .overlay(
                            Circle()
                                .stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                                    lineWidth: FCSizing.hairline
                                )
                        )
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(theme.colors.mutedText)
                        )
                }

                // Edit badge
                Circle()
                    .fill(Color.fcAccentPurple)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(x: 28, y: 28)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
        .accessibilityLabel("Choose profile photo")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Username Field

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: FCSpacing.xs) {
            Text("Username")
                .font(.custom(FCFontName.medium, size: 13, relativeTo: .caption))
                .foregroundStyle(theme.colors.mutedText)

            TextField("", text: $username)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.text)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .username)
                .frame(minHeight: FCSizing.minTapTarget)
                .overlay(alignment: .leading) {
                    if username.isEmpty {
                        Text("Choose a username")
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.mutedText.opacity(0.6))
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: username) { _, newValue in
                    validateUsername(newValue)
                }

            if let error = usernameError {
                Text(error)
                    .font(.custom(FCFontName.regular, size: 12, relativeTo: .caption2))
                    .foregroundStyle(theme.colors.statusRed)
            }
        }
    }

    // MARK: - Phone Field

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: FCSpacing.xs) {
            Text("Phone number")
                .font(.custom(FCFontName.medium, size: 13, relativeTo: .caption))
                .foregroundStyle(theme.colors.mutedText)

            HStack {
                TextField("", text: $phoneNumber)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.text)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
                    .frame(minHeight: FCSizing.minTapTarget)
                    .overlay(alignment: .leading) {
                        if phoneNumber.isEmpty {
                            Text("+1 (555) 000-0000")
                                .font(theme.typography.body)
                                .foregroundStyle(theme.colors.mutedText.opacity(0.6))
                                .allowsHitTesting(false)
                        }
                    }

                if !showOTPField && !phoneNumber.isEmpty {
                    Button {
                        sendVerificationCode()
                    } label: {
                        Text("Verify")
                            .font(.custom(FCFontName.semiBold, size: 14, relativeTo: .footnote))
                            .foregroundStyle(Color.fcAccentPurple)
                    }
                    .frame(minWidth: FCSizing.minTapTarget, minHeight: FCSizing.minTapTarget)
                }

                if isVerified {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.statusGreen)
                }
            }
        }
    }

    // MARK: - OTP Field

    private var otpField: some View {
        VStack(alignment: .leading, spacing: FCSpacing.xs) {
            Text("Verification code")
                .font(.custom(FCFontName.medium, size: 13, relativeTo: .caption))
                .foregroundStyle(theme.colors.mutedText)

            HStack {
                TextField("", text: $otpCode)
                    .font(.custom(FCFontName.semiBold, size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.colors.text)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .otp)
                    .frame(minHeight: FCSizing.minTapTarget)
                    .overlay(alignment: .leading) {
                        if otpCode.isEmpty {
                            Text("000000")
                                .font(.custom(FCFontName.semiBold, size: 20, relativeTo: .title3))
                                .foregroundStyle(theme.colors.mutedText.opacity(0.4))
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: otpCode) { _, code in
                        if code.count == 6 {
                            verifyOTP(code)
                        }
                    }

                if isVerifyingPhone {
                    ProgressView()
                        .tint(theme.colors.mutedText)
                }
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !username.isEmpty
        && username.count >= 3
        && usernameError == nil
        && isVerified
    }

    private func validateUsername(_ value: String) {
        if value.isEmpty {
            usernameError = nil
            return
        }
        if value.count < 3 {
            usernameError = "Username must be at least 3 characters"
            return
        }
        if value.count > 32 {
            usernameError = "Username must be 32 characters or fewer"
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            usernameError = "Only letters, numbers, hyphens, dots, underscores"
            return
        }
        usernameError = nil
    }

    private func sendVerificationCode() {
        withAnimation(SpringConstants.accessiblePageEntrance) {
            showOTPField = true
        }
        focusedField = .otp
    }

    private func verifyOTP(_ code: String) {
        isVerifyingPhone = true
        // Simulated verification delay for development
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isVerifyingPhone = false
            withAnimation(SpringConstants.accessiblePageEntrance) {
                isVerified = true
                showOTPField = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Create Profile Step") {
    ZStack {
        GradientBackground()
            .ignoresSafeArea()
        CreateProfileStep()
    }
    .environment(\.theme, Theme.shared)
}

#Preview("Create Profile Step - Light") {
    ZStack {
        Color.white.ignoresSafeArea()
        CreateProfileStep()
    }
    .environment(\.theme, Theme.resolved(for: .light))
    .preferredColorScheme(.light)
}
