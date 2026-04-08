import SwiftUI

struct AuthView: View {
    enum AuthMode: String, CaseIterable, Identifiable {
        case password = "Password"
        case magicLink = "Magic Link"

        var id: String { rawValue }
    }

    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var authMode: AuthMode = .magicLink
    @State private var email = ""
    @State private var password = ""
    @State private var magicLinkSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stitch")
                            .font(.system(size: 40, weight: .bold, design: .rounded))

                        Text("A fast receipt inbox built for collecting, reviewing, and batch uploading business receipts into Expensify.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    if magicLinkSent {
                        magicLinkSentView
                    } else {
                        signInForm
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            services.configuration.hasSupabaseAuth
                                ? "Live Supabase auth configured"
                                : "Demo auth active until BackendConfig.plist is filled in",
                            systemImage: services.configuration.hasSupabaseAuth
                                ? "checkmark.seal.fill"
                                : "hammer.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(services.configuration.hasSupabaseAuth ? .green : .orange)

                        Text("Core flows still work in demo mode so you can validate the product experience before wiring Supabase and the upload backend.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let message = sessionStore.lastMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(24)
            }
            .navigationBarHidden(true)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(red: 0.96, green: 0.98, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
    }

    @ViewBuilder
    private var signInForm: some View {
        VStack(spacing: 16) {
            Picker("Auth mode", selection: $authMode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: authMode) { _, _ in
                sessionStore.lastMessage = nil
            }

            TextField("Work email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            if authMode == .password {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }

            Button(action: submit) {
                HStack {
                    if sessionStore.isWorking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(authMode == .password ? "Sign in" : "Send magic link")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionStore.isWorking)
        }
    }

    @ViewBuilder
    private var magicLinkSentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Check your email")
                .font(.title2.weight(.semibold))

            Text("We sent a link to **\(email)**. Tap the link to sign in — it will open Stitch automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Use a different email") {
                magicLinkSent = false
                email = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func submit() {
        Task {
            switch authMode {
            case .password:
                await sessionStore.signIn(email: email, password: password)
            case .magicLink:
                await sessionStore.sendMagicLink(email: email)
                if services.configuration.hasSupabaseAuth {
                    magicLinkSent = true
                }
            }
        }
    }
}
