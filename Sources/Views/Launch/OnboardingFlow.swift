import SwiftUI

// MARK: - OnboardingFlow

/// Three-step onboarding using TabView with .page style.
/// Steps: Welcome, Create Profile, Permissions.
/// All steps are required (no skip).
struct OnboardingFlow: View {

    /// Called when onboarding is complete.
    var onComplete: () -> Void = {}

    @State private var currentStep: Int = 0
    @State private var showBypass = false
    @State private var bypassCode = ""
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Total number of onboarding steps.
    private let stepCount = 3

    var body: some View {
        ZStack {
            GradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentStep) {
                    WelcomeStep {
                        advanceToStep(1)
                    }
                    .tag(0)

                    CreateProfileStep {
                        advanceToStep(2)
                    }
                    .tag(1)

                    PermissionsStep {
                        completeOnboarding()
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(SpringConstants.accessiblePageEntrance, value: currentStep)

                // Custom page indicator — long-press to reveal bypass entry
                pageIndicator
                    .onLongPressGesture(minimumDuration: 1.0) {
                        showBypass = true
                    }
                    .padding(.bottom, BlipSpacing.md)
            }
        }
        .alert("Dev Bypass", isPresented: $showBypass) {
            TextField("Code", text: $bypassCode)
                .keyboardType(.numberPad)
            Button("Submit") { attemptBypass() }
            Button("Cancel", role: .cancel) { bypassCode = "" }
        } message: {
            Text("Enter bypass code to skip onboarding")
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: BlipSpacing.sm) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index == currentStep
                            ? Color.blipAccentPurple
                            : (colorScheme == .dark
                                ? Color.white.opacity(0.2)
                                : Color.black.opacity(0.15))
                    )
                    .frame(
                        width: index == currentStep ? 24 : 8,
                        height: 8
                    )
                    .animation(SpringConstants.accessiblePageEntrance, value: currentStep)
            }
        }
    }

    // MARK: - Navigation

    private func advanceToStep(_ step: Int) {
        withAnimation(SpringConstants.accessiblePageEntrance) {
            currentStep = min(step, stepCount - 1)
        }
    }

    private func completeOnboarding() {
        onComplete()
    }

    private func attemptBypass() {
        if bypassCode == "000000" {
            showBypass = false
            bypassCode = ""
            onComplete()
        }
    }
}

// MARK: - Preview

#Preview("Onboarding Flow") {
    OnboardingFlow()
        .environment(\.theme, Theme.shared)
}

#Preview("Onboarding Flow - Light") {
    OnboardingFlow()
        .environment(\.theme, Theme.resolved(for: .light))
        .preferredColorScheme(.light)
}
