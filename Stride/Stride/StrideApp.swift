import SwiftUI
import UIKit

@main
struct StrideApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(.brandGreen)
        }
    }
}

// Tap anywhere on the window to dismiss the keyboard without cancelling child taps.
private final class KeyboardDismissTapRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delegate = self
        addTarget(self, action: #selector(handleTap))
    }

    @objc private func handleTap() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }

    // Don't intercept taps that land on interactive controls — let buttons get clean touches.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is UIControl)
    }
}

// ── Root navigation ───────────────────────────────────────────────────────────
// Decides what to show based on auth + onboarding state. Transitions are
// animated so the app doesn't snap between very different contexts.

struct RootView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ZStack {
            switch appState.route {
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlowView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.route)
        .onAppear { installKeyboardDismissTap() }
    }

    private func installKeyboardDismissTap() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        // Only install once — check if already present.
        if window.gestureRecognizers?.contains(where: { $0 is KeyboardDismissTapRecognizer }) == true { return }
        window.addGestureRecognizer(KeyboardDismissTapRecognizer())
    }
}

// ── App-level state ───────────────────────────────────────────────────────────

enum AppRoute: Equatable {
    case auth
    case onboarding
    case main
}

@Observable
@MainActor
class AppState {
    var route: AppRoute = .auth
    var userID: String = ""
    var accessToken: String = ""

    init() {
        if let token = Keychain.get("access_token"),
           let uid   = Keychain.get("user_id") {
            accessToken = token
            userID = uid
            let onboarded = UserDefaults.standard.bool(forKey: "onboarding_complete")
            route = onboarded ? .main : .onboarding
        }
    }

    func signIn(userID: String, accessToken: String, refreshToken: String, isNewUser: Bool) {
        self.userID = userID
        self.accessToken = accessToken
        Keychain.set("user_id", value: userID)
        Keychain.set("access_token", value: accessToken)
        Keychain.set("refresh_token", value: refreshToken)
        Haptics.notify(.success)
        route = isNewUser ? .onboarding : .main
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
        Haptics.notify(.success)
        route = .main
    }

    func signOut() {
        Keychain.delete("access_token")
        Keychain.delete("refresh_token")
        Keychain.delete("user_id")
        UserDefaults.standard.removeObject(forKey: "onboarding_complete")
        userID = ""
        accessToken = ""
        route = .auth
    }
}
