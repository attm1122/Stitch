import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    Label("Scan paper receipts with the built-in document scanner.", systemImage: "doc.viewfinder")
                    Label("Import images from Photos or PDFs from Files.", systemImage: "square.and.arrow.down")
                    Label("Share receipts from other apps directly into Stitch.", systemImage: "square.and.arrow.up")
                }

                Section("Review") {
                    Label("Check extracted merchant, amount, and purchase date before upload.", systemImage: "text.magnifyingglass")
                    Label("Use selection mode to prepare a batch of receipts.", systemImage: "checklist")
                }

                Section("Upload") {
                    Label("Send ready receipts to your configured Expensify destination.", systemImage: "arrow.up.to.line")
                }
            }
            .navigationTitle("How Stitch Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
