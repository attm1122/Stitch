import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published var expensifyEmail: String
    @Published var isWorking = false
    @Published var lastMessage: String?

    private let authService: AuthServiceProtocol
    private let configuration: BackendConfiguration
    private let defaults: UserDefaults

    private enum Keys {
        static let session = "stitch.auth.session"
        static let expensifyEmail = "stitch.expensify.email"
    }

    init(authService: AuthServiceProtocol, configuration: BackendConfiguration, defaults: UserDefaults = .standard) {
        self.authService = authService
        self.configuration = configuration
        self.defaults = defaults
        self.expensifyEmail = defaults.string(forKey: Keys.expensifyEmail) ?? configuration.defaultExpensifyDestinationEmail

        if let data = defaults.data(forKey: Keys.session),
           let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
            self.session = session
        }
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var signedInEmail: String {
        session?.email ?? ""
    }

    var authModeDescription: String {
        authService.isConfigured ? "Supabase auth" : "Local demo auth"
    }

    func updateExpensifyEmail(_ email: String) {
        expensifyEmail = email
        defaults.set(email, forKey: Keys.expensifyEmail)
    }

    func signIn(email: String, password: String) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let session = try await authService.signInWithPassword(email: email, password: password)
            persist(session)
            lastMessage = authService.isConfigured ? "Signed in." : "Signed into demo mode. Add Supabase keys to enable live auth."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func sendMagicLink(email: String) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await authService.sendMagicLink(email: email)
            if authService.isConfigured {
                lastMessage = "Magic link sent to \(email)."
            } else {
                let demo = AuthSession(accessToken: UUID().uuidString, refreshToken: nil, email: email, expiresAt: nil)
                persist(demo)
                lastMessage = "Supabase isn’t configured yet, so Stitch opened a local demo session."
            }
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func handleIncoming(url: URL) async {
        do {
            let session = try await authService.session(from: url)
            persist(session)
            lastMessage = "Magic link verified."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        defaults.removeObject(forKey: Keys.session)
        lastMessage = "Signed out."
    }

    private func persist(_ session: AuthSession) {
        self.session = session
        defaults.set(try? JSONEncoder().encode(session), forKey: Keys.session)
    }
}
