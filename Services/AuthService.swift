import Foundation

@MainActor
protocol AuthServiceProtocol {
    var isConfigured: Bool { get }
    func signInWithPassword(email: String, password: String) async throws -> AuthSession
    func sendMagicLink(email: String) async throws
    func session(from callbackURL: URL) async throws -> AuthSession
    func refreshSession(refreshToken: String) async throws -> AuthSession
}

enum AuthError: LocalizedError {
    case malformedConfiguration
    case invalidCredentials
    case invalidCallback
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .malformedConfiguration:
            "Supabase configuration is missing or invalid."
        case .invalidCredentials:
            "Could not sign in with those credentials."
        case .invalidCallback:
            "The magic link callback did not include a usable session."
        case .refreshFailed:
            "Your session has expired. Please sign in again."
        }
    }
}

@MainActor
final class SupabaseAuthService: AuthServiceProtocol {
    private let configuration: BackendConfiguration

    init(configuration: BackendConfiguration) {
        self.configuration = configuration
    }

    var isConfigured: Bool {
        configuration.hasSupabaseAuth
    }

    func signInWithPassword(email: String, password: String) async throws -> AuthSession {
        guard let baseURL = configuration.supabaseURL else {
            return demoSession(email: email)
        }

        let endpoint = baseURL.appending(path: "auth/v1/token")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        guard let url = components?.url else {
            throw AuthError.malformedConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AuthError.invalidCredentials
        }

        let payload = try JSONDecoder().decode(SupabaseSessionResponse.self, from: data)
        return payload.authSession
    }

    func sendMagicLink(email: String) async throws {
        guard let baseURL = configuration.supabaseURL else { return }
        let endpoint = baseURL.appending(path: "auth/v1/otp")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MagicLinkRequest(
                email: email,
                createUser: true,
                emailRedirectTo: configuration.supabaseRedirectURL?.absoluteString
            )
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AuthError.malformedConfiguration
        }
    }

    func session(from callbackURL: URL) async throws -> AuthSession {
        let fragments = callbackURL.fragment?
            .split(separator: "&")
            .map(String.init) ?? []
        let pairs = fragments
            .compactMap { fragment -> (String, String)? in
                let pieces = fragment.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { return nil }
                return (pieces[0], pieces[1].removingPercentEncoding ?? pieces[1])
            }

        let dictionary = Dictionary(uniqueKeysWithValues: pairs)
        guard let accessToken = dictionary["access_token"] else {
            throw AuthError.invalidCallback
        }

        let email = dictionary["email"] ?? "unknown@example.com"
        let refreshToken = dictionary["refresh_token"]
        let expiresAt = dictionary["expires_at"]
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))

        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: email,
            expiresAt: expiresAt
        )
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        guard let baseURL = configuration.supabaseURL else {
            throw AuthError.refreshFailed
        }

        let endpoint = baseURL.appending(path: "auth/v1/token")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        guard let url = components?.url else {
            throw AuthError.malformedConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AuthError.refreshFailed
        }

        let payload = try JSONDecoder().decode(SupabaseSessionResponse.self, from: data)
        return payload.authSession
    }

    private func demoSession(email: String) -> AuthSession {
        AuthSession(
            accessToken: UUID().uuidString,
            refreshToken: nil,
            email: email,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}

private struct SupabaseSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: TimeInterval?
    let user: SupabaseUser?

    struct SupabaseUser: Decodable {
        let email: String?
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }

    var authSession: AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: user?.email ?? "",
            expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct MagicLinkRequest: Encodable {
    let email: String
    let createUser: Bool
    let emailRedirectTo: String?

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
        case emailRedirectTo = "email_redirect_to"
    }
}
