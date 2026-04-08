import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var expensifyEmail = ""
    @State private var showingSignOutConfirmation = false
    @State private var emailValidationMessage: String?

    private var isEmailValid: Bool {
        let trimmed = expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let emailRegex = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: emailRegex, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: sessionStore.signedInEmail)
                    LabeledContent("Auth mode", value: sessionStore.authModeDescription)
                    LabeledContent("Upload mode", value: services.configuration.uploadModeDescription)
                }

                Section {
                    TextField("Expensify email", text: $expensifyEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: expensifyEmail) { _, _ in
                            emailValidationMessage = isEmailValid ? nil : "Please enter a valid email address."
                        }

                    if let message = emailValidationMessage {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text("Stitch uses this email as the Expensify destination for batch upload.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Expensify destination")
                }

                if let message = sessionStore.lastMessage {
                    Section("Status") {
                        Text(message)
                    }
                }

                Section {
                    Button("Save settings") {
                        let trimmed = expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || isEmailValid {
                            sessionStore.updateExpensifyEmail(trimmed)
                            dismiss()
                        } else {
                            emailValidationMessage = "Please enter a valid email address before saving."
                        }
                    }
                    .disabled(!isEmailValid && !expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Sign out", role: .destructive) {
                        showingSignOutConfirmation = true
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
            .confirmationDialog(
                "Sign out of Stitch?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    sessionStore.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to upload receipts.")
            }
        }
    }
}
