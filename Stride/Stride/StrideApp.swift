import SwiftUI

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
