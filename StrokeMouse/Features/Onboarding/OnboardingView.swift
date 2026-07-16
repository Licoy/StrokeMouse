import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("onboarding.title"))
                .font(.largeTitle.weight(.bold))

            Text(L10n.string("onboarding.subtitle"))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                bullet("1", L10n.string("onboarding.step1"))
                bullet("2", L10n.string("onboarding.step2"))
                bullet("3", L10n.string("onboarding.step3"))
            }
            .padding(.vertical, 8)

            HStack {
                Button(L10n.string("permissions.openSettings")) {
                    appState.permissionManager.openAccessibilitySettings()
                }
                Spacer()
                Button(L10n.string("onboarding.continue")) {
                    appState.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
