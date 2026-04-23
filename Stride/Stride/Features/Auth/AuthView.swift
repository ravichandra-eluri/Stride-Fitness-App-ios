import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AppState.self) var appState
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Brand
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.brandGreenBg)
                        .frame(width: 80, height: 80)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.brandGreen)
                }
                Text("Stride")
                    .font(.titleLg)
                Text("Every step forward counts")
                    .font(.bodyLg)
                    .foregroundColor(.textMuted)
            }

            Spacer()

            // Value props
            VStack(alignment: .leading, spacing: Spacing.md) {
                featureRow(icon: "fork.knife", text: "Personalized meal plans every week")
                featureRow(icon: "chart.line.downtrend.xyaxis", text: "AI-powered weight loss plan")
                featureRow(icon: "bubble.left.fill", text: "Daily coaching messages")
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()

            // Sign in
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
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    Group {
                        if isLoading {
                            RoundedRectangle(cornerRadius: Radius.sm)
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
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.white)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.brandGreen)
                .frame(width: 28)
            Text(text)
                .font(.bodyMd)
        }
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

            Task {
                do {
                    let res = try await APIClient.shared.signInWithApple(
                        identityToken: token,
                        email: email,
                        fullName: fullName
                    )
                    await MainActor.run {
                        appState.signIn(
                            userID: res.userID,
                            accessToken: res.accessToken,
                            refreshToken: res.refreshToken,
                            isNewUser: res.isNewUser
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        }
    }
}
