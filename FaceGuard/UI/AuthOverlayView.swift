import AppKit
import SwiftUI

/// The SwiftUI view displayed inside the auth overlay panel.
/// Shows the locked app's icon, name, and authentication options.
struct AuthOverlayView: View {
    let appName: String
    let appIcon: NSImage
    let onAuthenticated: () -> Void
    let onCancel: () -> Void

    @StateObject private var authManager = AuthenticationManager.shared
    @State private var passwordInput: String = ""
    @State private var showPasswordField: Bool = false
    @State private var shakePassword: Bool = false

    var body: some View {
        ZStack {
            // Dark blurred background.
            VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Semi-transparent dark overlay for extra dimming.
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Content.
            VStack(spacing: 0) {
                Spacer()

                // Shield icon.
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hue: 0.58, saturation: 0.7, brightness: 0.95),
                                     Color(hue: 0.72, saturation: 0.6, brightness: 0.90)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 12)

                // App name.
                Text("FaceGuard")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 28)

                // App icon.
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
                    .padding(.bottom, 16)

                // "App Name is Locked".
                Text("\(appName) is Locked")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                Text("Authenticate to unlock this app")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 32)

                // Auth state feedback.
                authFeedbackView
                    .padding(.bottom, 16)

                // Auth methods.
                if showPasswordField {
                    passwordAuthView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    authButtonsView
                        .transition(.opacity)
                }

                Spacer()

                // Cancel button at bottom.
                Button(action: onCancel) {
                    Text("Cancel & Close App")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 360)
            .animation(.easeInOut(duration: 0.25), value: showPasswordField)
            .animation(.easeInOut(duration: 0.2), value: authManager.authState)
        }
        .onChange(of: authManager.authState) { newState in
            if case .success = newState {
                // Small delay for visual feedback before dismissing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onAuthenticated()
                    authManager.resetAttempts()
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var authFeedbackView: some View {
        switch authManager.authState {
        case .idle:
            EmptyView()
        case .authenticating(let method):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text("Authenticating with \(method.displayName)…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Authenticated!")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.8))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
        case .lockedOut(let duration):
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                Text("Too many failed attempts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange)
                Text("Try again in \(Int(duration)) seconds")
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var authButtonsView: some View {
        VStack(spacing: 12) {
            // Touch ID button (if available).
            if TouchIDAuth.shared.canUse {
                Button(action: authenticateWithTouchID) {
                    HStack(spacing: 10) {
                        Image(systemName: "touchid")
                            .font(.system(size: 18))
                        Text("Unlock with Touch ID")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            // Password button.
            Button(action: { withAnimation { showPasswordField = true } }) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 16))
                    Text("Use Password")
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
                .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 280)
    }

    @ViewBuilder
    private var passwordAuthView: some View {
        VStack(spacing: 16) {
            // Password input field.
            SecureField("Enter password", text: $passwordInput)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .offset(x: shakePassword ? -8 : 0)
                .animation(
                    shakePassword
                        ? Animation.default.repeatCount(4, autoreverses: true).speed(6)
                        : .default,
                    value: shakePassword
                )
                .onSubmit {
                    submitPassword()
                }

            HStack(spacing: 12) {
                // Back button.
                Button(action: {
                    withAnimation {
                        showPasswordField = false
                        passwordInput = ""
                    }
                }) {
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 80, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                // Unlock button.
                Button(action: submitPassword) {
                    Text("Unlock")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hue: 0.58, saturation: 0.6, brightness: 0.85),
                                            Color(hue: 0.65, saturation: 0.5, brightness: 0.75),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(passwordInput.isEmpty)
            }
        }
        .frame(maxWidth: 280)
    }

    // MARK: - Actions

    private func authenticateWithTouchID() {
        authManager.authenticateWithTouchID(appName: appName) { _ in }
    }

    private func submitPassword() {
        guard !passwordInput.isEmpty else { return }

        let success = authManager.authenticateWithPassword(passwordInput)
        if !success {
            // Shake animation on failure.
            shakePassword = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                shakePassword = false
            }
            passwordInput = ""
        }
    }
}

// MARK: - Visual Effect (NSVisualEffectView wrapper)

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
