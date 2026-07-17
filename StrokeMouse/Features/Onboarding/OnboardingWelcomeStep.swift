import SwiftUI

struct OnboardingWelcomeStep: View {
    var isAnimationPaused: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: BrandIconProvider.applicationIcon())
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            VStack(spacing: 8) {
                Text(L10n.string("onboarding.welcome.title"))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(L10n.string("onboarding.welcome.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingStrokeAnimationView(style: .welcome, isPaused: isAnimationPaused)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}
