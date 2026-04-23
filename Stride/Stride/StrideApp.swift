import SwiftUI

@main
struct StrideApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.light) // force light for v1
        }
    }
}

// ── Root navigation ───────────────────────────────────────────────────────────
// Decides what to show based on auth + onboarding state.

struct RootView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        if appState.route == .auth {
            AuthView()
        } else if appState.route == .onboarding {
            AnyView(OnboardingFlowView())
        } else {
            AnyView(MainTabView())
        }
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
        // Restore session from Keychain on launch
        if let token = Keychain.get("access_token"),
           let uid   = Keychain.get("user_id") {
            accessToken = token
            userID = uid
            // Check if onboarding is complete
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
        route = isNewUser ? .onboarding : .main
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
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
