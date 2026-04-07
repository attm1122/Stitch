import SwiftData
import SwiftUI

struct UploadQueueView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\UploadBatchRecord.createdAt, order: .reverse)]) private var batches: [UploadBatchRecord]
    @Query(sort: [SortDescriptor(\ReceiptRecord.updatedAt, order: .reverse)]) private var receipts: [ReceiptRecord]

    var body: some View {
        NavigationStack {
            List {
                Section("Sync history") {
                    if batches.isEmpty {
                        Text("No uploads yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(batches) { batch in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(batch.state.rawValue)
                                        .font(.headline)
                                    Spacer()
                                    Text(StitchFormatters.shortDate.string(from: batch.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(batch.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(batch.successCount) uploaded, \(batch.failureCount) failed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Failed receipts") {
                    let failed = receipts.filter { $0.uploadState == .failed }
                    if failed.isEmpty {
                        Text("No failed uploads.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(failed) { receipt in
                            VStack(alignment: .leading, spacing: 8) {
                                ReceiptRowView(receipt: receipt, isSelecting: false, isSelected: false)
                                Button("Retry upload") {
                                    Task {
                                        _ = await services.uploadService.upload(
                                            receipts: [receipt],
                                            expensifyEmail: sessionStore.expensifyEmail,
                                            session: sessionStore.session,
                                            in: modelContext
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Upload Queue")
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

