import SwiftData
import SwiftUI

struct UploadQueueView: View {
    let uploadCandidates: [ReceiptRecord]
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isUploading = false
    @State private var uploadResult: UploadBatchRecord?
    @State private var uploadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if uploadCandidates.isEmpty {
                        Text("No receipts are ready for upload. Mark receipts as 'Ready' in the detail view first.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(uploadCandidates) { receipt in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(receipt.displayMerchant)
                                        .font(.headline)
                                    Text(receipt.amount > 0
                                         ? StitchFormatters.currency(amount: receipt.amount, code: receipt.currencyCode)
                                         : "Amount missing")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: receipt.uploadState == .uploading ? "arrow.up.circle" : "checkmark.circle")
                                    .foregroundStyle(receipt.uploadState == .uploading ? .blue : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(uploadCandidates.count) receipt\(uploadCandidates.count == 1 ? "" : "s") queued")
                }

                if sessionStore.expensifyEmail.isEmpty {
                    Section {
                        Label("No Expensify email set. Add one in Settings before uploading.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                } else {
                    Section("Destination") {
                        LabeledContent("Expensify email", value: sessionStore.expensifyEmail)
                    }
                }

                if let result = uploadResult {
                    Section("Result") {
                        LabeledContent("Uploaded", value: "\(result.successCount)")
                        if result.failureCount > 0 {
                            LabeledContent("Failed", value: "\(result.failureCount)")
                                .foregroundStyle(.red)
                        }
                        Text(result.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = uploadError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Upload Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if uploadResult != nil {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if uploadResult == nil {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            Task { await startUpload() }
                        } label: {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isUploading ? "Uploading..." : "Upload \(uploadCandidates.count) Receipt\(uploadCandidates.count == 1 ? "" : "s")")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isUploading ||
                            uploadCandidates.isEmpty ||
                            sessionStore.expensifyEmail.isEmpty
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
    }

    private func startUpload() async {
        isUploading = true
        defer { isUploading = false }

        uploadError = nil

        let result = await services.uploadService.upload(
            receipts: uploadCandidates,
            expensifyEmail: sessionStore.expensifyEmail,
            sessionStore: sessionStore,
            in: modelContext
        )

        uploadResult = result

        if result.state == .failed {
            uploadError = result.message
        }
    }
}
