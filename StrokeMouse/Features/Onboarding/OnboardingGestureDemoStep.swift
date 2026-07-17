import SwiftUI

struct OnboardingGestureDemoStep: View {
    var isAnimationPaused: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(L10n.string("onboarding.demo.title"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(L10n.string("onboarding.demo.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingStrokeAnimationView(style: .demo, lineWidth: 4.5, isPaused: isAnimationPaused)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )

            HStack(spacing: 12) {
                stageChip(icon: "hand.point.up.left.fill", title: L10n.string("onboarding.demo.hold"))
                stageChip(icon: "scribble.variable", title: L10n.string("onboarding.demo.draw"))
                stageChip(icon: "sparkles", title: L10n.string("onboarding.demo.release"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stageChip(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
