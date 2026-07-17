import SwiftUI

struct OnboardingDoneStep: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let trusted = appState.permissionManager.isAccessibilityTrusted

        VStack(spacing: 18) {
            Image(systemName: trusted ? "party.popper.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(trusted ? Color.accentColor : Color.orange)
                .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: !trusted)

            VStack(spacing: 8) {
                Text(L10n.string(
                    trusted
                        ? "onboarding.done.titleReady"
                        : "onboarding.done.titlePartial"
                ))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

                Text(L10n.string(
                    trusted
                        ? "onboarding.done.bodyReady"
                        : "onboarding.done.bodyPartial"
                ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if trusted {
                Label(
                    L10n.string("onboarding.done.listening"),
                    systemImage: "waveform.path.ecg"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}
