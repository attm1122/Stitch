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

private let uploadSessionIdentifier = "com.attm1122.Stitch.upload"

enum UploadExecutionMode {
    case demo
    case live(endpoint: URL)
}

@MainActor
final class UploadService {
    private let configuration: BackendConfiguration
    private let fileStore: ReceiptFileStore

    private static let backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: uploadSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config)
    }()

    init(configuration: BackendConfiguration, fileStore: ReceiptFileStore) {
        self.configuration = configuration
        self.fileStore = fileStore
    }

    static func uploadExecutionMode(
        configuration: BackendConfiguration,
        expensifyEmail: String
    ) throws -> UploadExecutionMode {
        guard let endpoint = configuration.batchUploadEndpoint else {
            return .demo
        }

        let trimmedEmail = expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw UploadError.missingDestinationEmail
        }
        guard isValidDestinationEmail(trimmedEmail) else {
            throw UploadError.invalidDestinationEmail
        }

        return .live(endpoint: endpoint)
    }

    static func isValidDestinationEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    func upload(
        receipts: [ReceiptRecord],
        expensifyEmail: String,
        sessionStore: SessionStore,
        in context: ModelContext
    ) async -> UploadBatchRecord {
        let trimmedEmail = expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionMode: UploadExecutionMode

        do {
            executionMode = try Self.uploadExecutionMode(
                configuration: configuration,
                expensifyEmail: trimmedEmail
            )
        } catch {
            let batch = UploadBatchRecord(
                state: .failed,
                receiptIdentifiersCSV: receipts.map(\.id.uuidString).joined(separator: ","),
                successCount: 0,
                failureCount: receipts.count,
                message: error.localizedDescription
            )
            context.insert(batch)

            for receipt in receipts {
                receipt.uploadState = .failed
                receipt.lastUploadAttemptAt = .now
                receipt.lastUploadError = error.localizedDescription
            }

            try? context.save()
            return batch
        }

        let batch = UploadBatchRecord(
            state: .uploading,
            receiptIdentifiersCSV: receipts.map(\.id.uuidString).joined(separator: ","),
            successCount: 0,
            failureCount: 0,
            message: configuration.hasLiveUpload
                ? "Uploading receipts to Expensify."
                : "Demo upload completed locally."
        )
        context.insert(batch)

        for receipt in receipts {
            receipt.uploadState = .uploading
            receipt.lastUploadAttemptAt = .now
            receipt.lastUploadError = ""
        }

        do {
            let results: [String: BatchUploadResponseBody.ItemResult]

            switch executionMode {
            case .live(let endpoint):
                guard let validSession = await sessionStore.validSession() else {
                    throw UploadError.sessionExpired
                }
                results = try await uploadViaEndpoint(
                    receipts: receipts,
                    expensifyEmail: trimmedEmail,
                    endpoint: endpoint,
                    session: validSession
                )
            case .demo:
                results = try await demoUpload(receipts: receipts)
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
            batch.state = batch.failureCount == 0
                ? .completed
                : (batch.successCount > 0 ? .partial : .failed)
            batch.message = batch.failureCount == 0
                ? "Uploaded \(batch.successCount) receipts."
                : "Uploaded \(batch.successCount), failed \(batch.failureCount)."

            do {
                try context.save()
            } catch {
                batch.message += " (Warning: local save failed — \(error.localizedDescription))"
            }

        } catch {
            batch.completedAt = .now
            batch.state = .failed
            batch.message = error.localizedDescription

            for receipt in receipts {
                receipt.uploadState = .failed
                receipt.lastUploadError = error.localizedDescription
            }

            do {
                try context.save()
            } catch {
            }
        }

        return batch
    }

    private func demoUpload(receipts: [ReceiptRecord]) async throws -> [String: BatchUploadResponseBody.ItemResult] {
        try await Task.sleep(for: .milliseconds(700))
        let results = receipts.map { receipt in
            BatchUploadResponseBody.ItemResult(
                receiptId: receipt.id.uuidString,
                status: receipt.amount > 0 ? "uploaded" : "failed",
                message: receipt.amount > 0
                    ? "Demo upload succeeded."
                    : "Amount must be greater than zero."
            )
        }
        return Dictionary(uniqueKeysWithValues: results.map { ($0.receiptId, $0) })
    }

    private func uploadViaEndpoint(
        receipts: [ReceiptRecord],
        expensifyEmail: String,
        endpoint: URL,
        session: AuthSession
    ) async throws -> [String: BatchUploadResponseBody.ItemResult] {
        var payloadReceipts: [BatchUploadRequestBody.UploadReceipt] = []

        for receipt in receipts {
            let data = try await fileStore.fileData(for: receipt.localRelativePath)
            let dateString = receipt.purchaseDate.map(ISO8601DateFormatter().string(from:))
            payloadReceipts.append(
                BatchUploadRequestBody.UploadReceipt(
                    receiptId: receipt.id.uuidString,
                    fileName: receipt.fileName,
                    contentType: receipt.contentType,
                    merchant: receipt.merchant,
                    amount: receipt.amount,
                    currencyCode: receipt.currencyCode,
                    purchaseDate: dateString,
                    base64Data: data.base64EncodedString()
                )
            )
        }

        let body = BatchUploadRequestBody(expensifyEmail: expensifyEmail, receipts: payloadReceipts)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw UploadError.sessionExpired
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UploadError.serverError(httpResponse.statusCode)
        }

        let responseBody = try JSONDecoder().decode(BatchUploadResponseBody.self, from: data)
        return Dictionary(uniqueKeysWithValues: responseBody.results.map { ($0.receiptId, $0) })
    }
}

enum UploadError: LocalizedError {
    case missingDestinationEmail
    case invalidDestinationEmail
    case sessionExpired
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingDestinationEmail:
            "Add your Expensify email in Settings before uploading receipts."
        case .invalidDestinationEmail:
            "Enter a valid Expensify email address before uploading receipts."
        case .sessionExpired:
            "Your session has expired. Please sign in again."
        case .invalidResponse:
            "The server returned an unexpected response."
        case .serverError(let code):
            "Upload failed with server error \(code). Please try again."
        }
    }
}
