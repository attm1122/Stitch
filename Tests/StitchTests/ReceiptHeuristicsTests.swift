import Foundation
import SwiftData
import Testing
@testable import Stitch

struct ReceiptHeuristicsTests {
    @Test
    func parsesMerchantAmountAndDate() {
        let parser = ReceiptHeuristicParser()
        let text = """
        COFFEE REPUBLIC
        TAX INVOICE
        03/14/2026
        TOTAL $18.40
        """

        let result = parser.parse(text: text, fallbackMerchant: "fallback.jpg", pageCount: 1)

        #expect(result.merchant == "COFFEE REPUBLIC")
        #expect(result.amount == 18.40)
        #expect(result.purchaseDate != nil)
    }

    @Test
    func producesStableDuplicateFingerprint() {
        let parser = ReceiptHeuristicParser()
        let text = """
        HOTEL CENTRAL
        2026-02-09
        TOTAL AUD 219.90
        """
        let result = parser.parse(text: text, fallbackMerchant: "hotel.pdf", pageCount: 2)

        let fingerprintA = parser.duplicateFingerprint(for: result)
        let fingerprintB = parser.duplicateFingerprint(for: result)

        #expect(fingerprintA == fingerprintB)
    }

    @Test
    func liveUploadRequiresDestinationEmail() throws {
        let configuration = BackendConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: "",
            supabaseRedirectURL: nil,
            batchUploadEndpoint: URL(string: "https://example.com/upload"),
            defaultExpensifyDestinationEmail: ""
        )

        do {
            try UploadService.uploadExecutionMode(configuration: configuration, expensifyEmail: " ")
            Issue.record("Expected live upload validation to reject a blank Expensify email.")
        } catch let error as UploadError {
            switch error {
            case .missingDestinationEmail:
                break
            default:
                Issue.record("Expected a missing destination email error, got \(error.localizedDescription).")
            }
        }
    }

    @Test
    func liveUploadUsesConfiguredEndpointWhenEmailIsValid() throws {
        let endpoint = try #require(URL(string: "https://example.com/upload"))
        let configuration = BackendConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: "",
            supabaseRedirectURL: nil,
            batchUploadEndpoint: endpoint,
            defaultExpensifyDestinationEmail: ""
        )

        let mode = try UploadService.uploadExecutionMode(
            configuration: configuration,
            expensifyEmail: "receipts@example.com"
        )

        switch mode {
        case .live(let resolvedEndpoint):
            #expect(resolvedEndpoint == endpoint)
        case .demo:
            Issue.record("Expected live upload mode when the endpoint and email are both present.")
        }
    }

    @Test
    func photoImportsPreserveOriginalTypeMetadata() async throws {
        let receiptsDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)

        let fileStore = ReceiptFileStore(
            fileManager: .default,
            receiptsDirectoryURL: receiptsDirectory
        )
        let stored = try await fileStore.persistPhotoData(
            Data([0x01, 0x02, 0x03]),
            suggestedName: "receipt.heic",
            contentType: "image/heic"
        )

        #expect(stored.relativePath.hasSuffix(".heic"))
        #expect(stored.contentType == "image/heic")
    }

    @Test
    @MainActor
    func failedSharedImportsStayQueuedForRetry() async throws {
        let manifestURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-pending-shares.json")
        let envelopes = [
            PendingSharedReceiptEnvelope(
                fileName: "ok.pdf",
                contentType: "application/pdf",
                dataBase64: Data("ok".utf8).base64EncodedString()
            ),
            PendingSharedReceiptEnvelope(
                fileName: "retry.pdf",
                contentType: "application/pdf",
                dataBase64: Data("retry".utf8).base64EncodedString()
            ),
        ]
        try JSONEncoder().encode(envelopes).write(to: manifestURL, options: .atomic)

        let inbox = AppGroupInboxService(fileManager: .default, manifestURL: manifestURL) { _, fileName, _, _ in
            if fileName == "retry.pdf" {
                throw TestImportError.syntheticFailure
            }
        }
        let context = try makeInMemoryModelContext()

        let importedCount = try await inbox.ingestPendingShares(into: context)

        #expect(importedCount == 1)

        let remainingData = try Data(contentsOf: manifestURL)
        let remaining = try JSONDecoder().decode([PendingSharedReceiptEnvelope].self, from: remainingData)
        #expect(remaining.count == 1)
        #expect(remaining.first?.fileName == "retry.pdf")
    }
}

private enum TestImportError: Error {
    case syntheticFailure
}

private func makeInMemoryModelContext() throws -> ModelContext {
    let schema = Schema([
        ReceiptRecord.self,
        UploadBatchRecord.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}
