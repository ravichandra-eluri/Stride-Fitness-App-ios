import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AppState.self) var appState
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        WScreenBackground {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: Spacing.lg)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.brandGreen, Color.brandPurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)
                            Image(systemName: "figure.walk.motion")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stride")
                                .font(.titleLg)
                            Text("Fitness that feels coached, calm, and personal.")
                                .font(.bodyMd)
                                .foregroundColor(.textMuted)
                        }
                    }

                    WHeroCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Build a plan that adapts to your meals, your routine, and your real progress.")
                                .font(.titleMd)
                            HStack(spacing: Spacing.sm) {
                                statPill(value: "7d", label: "meal plans")
                                statPill(value: "AI", label: "daily coach")
                                statPill(value: "1x", label: "simple logging")
                            }
                        }
                    }
                }

                WHeroCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("What you get")
                            .font(.labelMd)
                            .foregroundColor(.textMuted)
                        featureRow(icon: "fork.knife", text: "Personalized weekly meal structure")
                        featureRow(icon: "chart.line.uptrend.xyaxis", text: "Weight tracking with clear trend feedback")
                        featureRow(icon: "bubble.left.and.bubble.right.fill", text: "Daily coaching that reacts to your logs")
                    }
                }

                Spacer()

                VStack(spacing: Spacing.md) {
                    if let error {
                        Text(error)
                            .font(.bodySm)
                            .foregroundColor(.danger)
                            .multilineTextAlignment(.center)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        Group {
                            if isLoading {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.black.opacity(0.4))
                                ProgressView().tint(.white)
                            }
                        }
                    )
                    .disabled(isLoading)

                    Text("By continuing, you agree to our Terms and Privacy Policy")
                        .font(.bodySm)
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, Spacing.xxl)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.brandGreen.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.brandGreen)
            }
            Text(text)
                .font(.bodyMd)
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.labelMd)
                .foregroundColor(.primary)
            Text(label)
                .font(.bodySm)
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            if (err as NSError).code != ASAuthorizationError.canceled.rawValue {
                self.error = err.localizedDescription
            }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                self.error = "Sign in failed — please try again"
                return
            }

            let email    = cred.email ?? ""
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")

            isLoading = true
            error = nil

            Task { @MainActor in
                do {
                    let res = try await APIClient.shared.signInWithApple(
                        identityToken: token,
                        email: email,
                        fullName: fullName
                    )
                    appState.signIn(
                        userID: res.userId,
                        accessToken: res.accessToken,
                        refreshToken: res.refreshToken,
                        isNewUser: res.isNewUser
                    )
                } catch {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
