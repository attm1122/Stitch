import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "doc.viewfinder.fill",
            iconColor: .blue,
            title: "Capture receipts",
            body: "Scan paper receipts with your camera, import PDFs or images from Files, or use your Photos library. You can also share receipts directly into Stitch from any app."
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            iconColor: .green,
            title: "Review and confirm",
            body: "Stitch reads the merchant name, amount, and date automatically. Tap any receipt to fix details before uploading. Receipts marked 'Ready' are queued for batch upload."
        ),
        OnboardingStep(
            icon: "arrow.up.to.line.circle.fill",
            iconColor: .indigo,
            title: "Batch upload to Expensify",
            body: "Set your Expensify email in Settings, then tap 'Ready to Upload' to send all confirmed receipts in one go. Stitch emails them directly to Expensify for expense reporting."
        ),
        OnboardingStep(
            icon: "square.and.arrow.down.fill",
            iconColor: .teal,
            title: "Use the Share Sheet",
            body: "Found a receipt in Mail or Safari? Tap the share button and select Stitch. The receipt lands in your inbox automatically when you next open the app."
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Text("Welcome to Stitch")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Your receipt inbox, built for Expensify")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 24) {
                        ForEach(steps) { step in
                            OnboardingStepRow(step: step)
                        }
                    }
                    .padding(.horizontal, 4)

                    Button("Get started") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct OnboardingStep: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}

private struct OnboardingStepRow: View {
    let step: OnboardingStep

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: step.icon)
                .font(.title2)
                .foregroundStyle(step.iconColor)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                Text(step.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
