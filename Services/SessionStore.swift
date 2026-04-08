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
    private let keychain: KeychainStore
    private let defaults: UserDefaults

    private enum Keys {
        static let session = "stitch.auth.session"
        static let expensifyEmail = "stitch.expensify.email"
    }

    init(
        authService: AuthServiceProtocol,
        configuration: BackendConfiguration,
        keychain: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.authService = authService
        self.configuration = configuration
        self.keychain = keychain
        self.defaults = defaults
        self.expensifyEmail = defaults.string(forKey: Keys.expensifyEmail)
            ?? configuration.defaultExpensifyDestinationEmail

        self.session = keychain.load(AuthSession.self, forKey: Keys.session)
    }

    var isAuthenticated: Bool {
        guard let session else { return false }
        if let expiresAt = session.expiresAt {
            return expiresAt > Date()
        }
        return true
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

    func validSession() async -> AuthSession? {
        guard var current = session else { return nil }

        if let expiresAt = current.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
            if let refreshToken = current.refreshToken,
               let refreshed = try? await authService.refreshSession(refreshToken: refreshToken) {
                persist(refreshed)
                current = refreshed
            } else {
                signOut()
                return nil
            }
        }

        return current
    }

    func signIn(email: String, password: String) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let session = try await authService.signInWithPassword(email: email, password: password)
            persist(session)
            lastMessage = authService.isConfigured
                ? "Signed in."
                : "Signed into demo mode. Add Supabase keys to enable live auth."
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
                lastMessage = "Magic link sent to \(email). Check your email and tap the link to sign in."
            } else {
                let demo = AuthSession(
                    accessToken: UUID().uuidString,
                    refreshToken: nil,
                    email: email,
                    expiresAt: Date().addingTimeInterval(3600)
                )
                persist(demo)
                lastMessage = "Supabase isn't configured yet, so Stitch opened a local demo session."
            }
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func handleIncoming(url: URL) async {
        do {
            let session = try await authService.session(from: url)
            persist(session)
            lastMessage = "Magic link verified. You're signed in."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        keychain.delete(forKey: Keys.session)
        lastMessage = "Signed out."
    }

    private func persist(_ session: AuthSession) {
        self.session = session
        do {
            try keychain.save(session, forKey: Keys.session)
        } catch {
            lastMessage = "Warning: Could not securely save your session. You may need to sign in again after restarting the app."
        }
    }
}
