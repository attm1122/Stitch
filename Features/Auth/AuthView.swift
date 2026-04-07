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

                    VStack(spacing: 16) {
                        Picker("Auth mode", selection: $authMode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Work email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.roundedBorder)

                        if authMode == .password {
                            SecureField("Password", text: $password)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Label(services.configuration.hasSupabaseAuth ? "Live Supabase auth configured" : "Demo auth active until BackendConfig is filled in", systemImage: services.configuration.hasSupabaseAuth ? "checkmark.seal.fill" : "hammer.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(services.configuration.hasSupabaseAuth ? .green : .orange)

                        Text("Core flows still work in demo mode so you can validate the product experience before wiring Supabase and the upload backend.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let message = sessionStore.lastMessage {
                            Text(message)
                                .font(.footnote)
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

    private func submit() {
        Task {
            switch authMode {
            case .password:
                await sessionStore.signIn(email: email, password: password)
            case .magicLink:
                await sessionStore.sendMagicLink(email: email)
            }
        }
    }
}

