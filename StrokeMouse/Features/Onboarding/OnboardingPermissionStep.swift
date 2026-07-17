import AppKit
import SwiftUI

struct OnboardingPermissionStep: View {
    @Environment(AppState.self) private var appState
    var onGranted: (() -> Void)?

    var body: some View {
        let trusted = appState.permissionManager.isAccessibilityTrusted

        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill((trusted ? Color.green : Color.accentColor).opacity(0.12))
                    .frame(width: 88, height: 88)

                Image(systemName: trusted ? "checkmark.seal.fill" : "hand.raised.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(trusted ? Color.green : Color.accentColor)
                    .symbolEffect(.bounce, value: trusted)
            }

            VStack(spacing: 8) {
                Text(L10n.string("onboarding.permission.title"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(L10n.string(
                    trusted
                        ? "onboarding.permission.granted"
                        : "onboarding.permission.body"
                ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            statusBadge(trusted: trusted)

            if !trusted {
                VStack(alignment: .leading, spacing: 8) {
                    tipRow(number: "1", text: L10n.string("onboarding.permission.tip1"))
                    tipRow(number: "2", text: L10n.string("onboarding.permission.tip2"))
                    tipRow(number: "3", text: L10n.string("onboarding.permission.tip3"))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: trusted) { _, isTrusted in
            if isTrusted {
                onGranted?()
            }
        }
    }

    private func statusBadge(trusted: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(trusted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(L10n.string(
                trusted
                    ? "onboarding.permission.statusGranted"
                    : "onboarding.permission.statusWaiting"
            ))
            .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill((trusted ? Color.green : Color.orange).opacity(0.12))
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: trusted)
    }

    private func tipRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
