import SwiftUI

@main
struct StrideApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light) // force light for v1
        }
    }
}

// ── Root navigation ───────────────────────────────────────────────────────────
// Decides what to show based on auth + onboarding state.

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.route {
            case .auth:
                AuthView()
            case .onboarding:
                OnboardingFlowView()
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.route)
    }
}

// ── App-level state ───────────────────────────────────────────────────────────

enum AppRoute: Equatable {
    case auth
    case onboarding
    case main
}

@MainActor
class AppState: ObservableObject {
    @Published var route: AppRoute = .auth
    @Published var userID: String = ""
    @Published var accessToken: String = ""

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
