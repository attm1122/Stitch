import Foundation
import SwiftData

struct PendingSharedReceiptEnvelope: Codable {
    let fileName: String
    let contentType: String
    let dataBase64: String
}

@MainActor
final class AppGroupInboxService {
    private let groupIdentifier = "group.com.attm1122.Stitch"
    private let manifestFileName = "pending-shares.json"
    private let importer: ReceiptImportCoordinator

    init(importer: ReceiptImportCoordinator) {
        self.importer = importer
    }

    func ingestPendingShares(into context: ModelContext) async throws -> Int {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            return 0
        }

        let manifestURL = containerURL.appending(path: manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return 0
        }

        let data = try Data(contentsOf: manifestURL)
        let envelopes = try JSONDecoder().decode([PendingSharedReceiptEnvelope].self, from: data)

        for envelope in envelopes {
            guard let binaryData = Data(base64Encoded: envelope.dataBase64) else { continue }
            _ = try await importer.importSharedData(
                binaryData,
                fileName: envelope.fileName,
                contentType: envelope.contentType,
                into: context
            )
        }

        try FileManager.default.removeItem(at: manifestURL)
        return envelopes.count
    }
}

