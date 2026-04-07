import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var expensifyEmail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: sessionStore.signedInEmail)
                    LabeledContent("Auth mode", value: sessionStore.authModeDescription)
                    LabeledContent("Upload mode", value: services.configuration.uploadModeDescription)
                }

                Section("Expensify destination") {
                    TextField("Expensify email", text: $expensifyEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Stitch uses this email as the Expensify destination for batch upload.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = sessionStore.lastMessage {
                    Section("Status") {
                        Text(message)
                    }
                }

                Section {
                    Button("Save settings") {
                        sessionStore.updateExpensifyEmail(expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }

                    Button("Sign out", role: .destructive) {
                        sessionStore.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                expensifyEmail = sessionStore.expensifyEmail
            }
        }
    }
}

