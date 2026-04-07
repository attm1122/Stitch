import Foundation
import SwiftData

struct BatchUploadRequestBody: Encodable {
    struct UploadReceipt: Encodable {
        let receiptId: String
        let fileName: String
        let contentType: String
        let merchant: String
        let amount: Double
        let currencyCode: String
        let purchaseDate: String?
        let base64Data: String
    }

    let expensifyEmail: String
    let receipts: [UploadReceipt]
}

struct BatchUploadResponseBody: Decodable {
    struct ItemResult: Decodable {
        let receiptId: String
        let status: String
        let message: String?
    }

    let batchId: String
    let results: [ItemResult]
}

@MainActor
final class UploadService {
    private let configuration: BackendConfiguration
    private let fileStore: ReceiptFileStore

    init(configuration: BackendConfiguration, fileStore: ReceiptFileStore) {
        self.configuration = configuration
        self.fileStore = fileStore
    }

    func upload(
        receipts: [ReceiptRecord],
        expensifyEmail: String,
        session: AuthSession?,
        in context: ModelContext
    ) async -> UploadBatchRecord {
        let batch = UploadBatchRecord(
            state: .uploading,
            receiptIdentifiersCSV: receipts.map(\.id.uuidString).joined(separator: ","),
            successCount: 0,
            failureCount: 0,
            message: configuration.batchUploadEndpoint == nil ? "Demo upload completed locally." : "Uploading receipts to Expensify."
        )
        context.insert(batch)

        for receipt in receipts {
            receipt.uploadState = .uploading
            receipt.lastUploadAttemptAt = .now
            receipt.lastUploadError = ""
        }

        do {
            let results = if let endpoint = configuration.batchUploadEndpoint, !expensifyEmail.isEmpty {
                try await uploadViaEndpoint(receipts: receipts, expensifyEmail: expensifyEmail, endpoint: endpoint, session: session)
            } else {
                try await demoUpload(receipts: receipts)
            }

            for receipt in receipts {
                let result = results[receipt.id.uuidString]
                if result?.status == "uploaded" {
                    receipt.uploadState = .uploaded
                    receipt.status = .uploaded
                    receipt.uploadedAt = .now
                    batch.successCount += 1
                } else {
                    receipt.uploadState = .failed
                    receipt.lastUploadError = result?.message ?? "Upload failed."
                    batch.failureCount += 1
                }
            }

            batch.completedAt = .now
            batch.state = batch.failureCount == 0 ? .completed : (batch.successCount > 0 ? .partial : .failed)
            batch.message = batch.failureCount == 0 ? "Uploaded \(batch.successCount) receipts." : "Uploaded \(batch.successCount), failed \(batch.failureCount)."
            try? context.save()
        } catch {
            batch.completedAt = .now
            batch.state = .failed
            batch.message = error.localizedDescription

            for receipt in receipts {
                receipt.uploadState = .failed
                receipt.lastUploadError = error.localizedDescription
            }

            try? context.save()
        }

        return batch
    }

    private func demoUpload(receipts: [ReceiptRecord]) async throws -> [String: BatchUploadResponseBody.ItemResult] {
        try await Task.sleep(for: .milliseconds(700))
        let results = receipts.map { receipt in
            BatchUploadResponseBody.ItemResult(
                receiptId: receipt.id.uuidString,
                status: receipt.amount > 0 ? "uploaded" : "failed",
                message: receipt.amount > 0 ? "Demo upload succeeded." : "Amount must be greater than zero."
            )
        }
        return Dictionary(uniqueKeysWithValues: results.map { ($0.receiptId, $0) })
    }

    private func uploadViaEndpoint(
        receipts: [ReceiptRecord],
        expensifyEmail: String,
        endpoint: URL,
        session: AuthSession?
    ) async throws -> [String: BatchUploadResponseBody.ItemResult] {
        var payloadReceipts: [BatchUploadRequestBody.UploadReceipt] = []

        for receipt in receipts {
            let data = try await fileStore.fileData(for: receipt.localRelativePath)
            payloadReceipts.append(
                BatchUploadRequestBody.UploadReceipt(
                    receiptId: receipt.id.uuidString,
                    fileName: receipt.fileName,
                    contentType: receipt.contentType,
                    merchant: receipt.merchant,
                    amount: receipt.amount,
                    currencyCode: receipt.currencyCode,
                    purchaseDate: receipt.purchaseDate.map(Self.dayOnlyString(from:)),
                    base64Data: data.base64EncodedString()
                )
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            BatchUploadRequestBody(expensifyEmail: expensifyEmail, receipts: payloadReceipts)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(BatchUploadResponseBody.self, from: data)
        return Dictionary(uniqueKeysWithValues: payload.results.map { ($0.receiptId, $0) })
    }

    private static func dayOnlyString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
