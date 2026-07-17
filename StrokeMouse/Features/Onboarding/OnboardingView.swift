import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case permission
    case demo
    case done
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: OnboardingStep = .welcome
    @State private var didAutoAdvanceFromPermission = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 20)
                .padding(.bottom, 12)

            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: step)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .padding(.top, 8)
        }
        .frame(width: 560, height: 480)
        .interactiveDismissDisabled(true)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        let pauseMotion = appState.permissionManager.isAuthorizationFlowActive
        switch step {
        case .welcome:
            OnboardingWelcomeStep(isAnimationPaused: pauseMotion)
        case .permission:
            OnboardingPermissionStep {
                guard !didAutoAdvanceFromPermission else { return }
                didAutoAdvanceFromPermission = true
                // Brief pause so the success badge is readable.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    withAnimation {
                        if step == .permission {
                            step = .demo
                        }
                    }
                }
            }
        case .demo:
            OnboardingGestureDemoStep(isAnimationPaused: pauseMotion)
        case .done:
            OnboardingDoneStep()
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: s == step ? 22 : 8, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)"))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button(L10n.string("onboarding.back")) {
                    withAnimation {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button(L10n.string("onboarding.skip")) {
                    finish()
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button(L10n.string("onboarding.next")) {
                withAnimation { step = .permission }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .permission:
            if appState.permissionManager.isAccessibilityTrusted {
                Button(L10n.string("onboarding.next")) {
                    withAnimation { step = .demo }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.string("onboarding.permission.authorize")) {
                    appState.permissionManager.authorizeAccessibility(
                        sourceFrameInScreen: Self.clickSourceFrame()
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button(L10n.string("onboarding.permission.skip")) {
                    withAnimation { step = .demo }
                }
            }

        case .demo:
            Button(L10n.string("onboarding.next")) {
                withAnimation { step = .done }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

        case .done:
            Button(L10n.string("onboarding.continue")) {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func finish() {
        appState.completeOnboarding()
        dismiss()
    }

    private static func clickSourceFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }
}
