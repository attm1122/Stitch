import Foundation
import SwiftData

struct PendingSharedReceiptEnvelope: Codable {
    let fileName: String
    let contentType: String
    let dataBase64: String
}

@MainActor
final class AppGroupInboxService {
    typealias SharedReceiptImporter = @MainActor (Data, String, String, ModelContext) async throws -> Void

    private let fileManager: FileManager
    private let manifestURLProvider: () -> URL?
    private let importSharedReceipt: SharedReceiptImporter

    init(
        importer: ReceiptImportCoordinator,
        fileManager: FileManager = .default,
        groupIdentifier: String = "group.com.attm1122.Stitch",
        manifestFileName: String = "pending-shares.json"
    ) {
        self.fileManager = fileManager
        self.manifestURLProvider = {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
                .appending(path: manifestFileName)
        }
        self.importSharedReceipt = { data, fileName, contentType, context in
            _ = try await importer.importSharedData(
                data,
                fileName: fileName,
                contentType: contentType,
                into: context
            )
        }
    }

    init(
        fileManager: FileManager = .default,
        manifestURL: URL,
        importSharedReceipt: @escaping SharedReceiptImporter
    ) {
        self.fileManager = fileManager
        self.manifestURLProvider = { manifestURL }
        self.importSharedReceipt = importSharedReceipt
    }

    func ingestPendingShares(into context: ModelContext) async throws -> Int {
        guard let manifestURL = manifestURLProvider() else {
            return 0
        }
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return 0
        }

        let data = try Data(contentsOf: manifestURL)
        let envelopes = try JSONDecoder().decode([PendingSharedReceiptEnvelope].self, from: data)

        guard !envelopes.isEmpty else {
            try? fileManager.removeItem(at: manifestURL)
            return 0
        }

        var importedCount = 0
        var remainingEnvelopes: [PendingSharedReceiptEnvelope] = []
        for envelope in envelopes {
            guard let binaryData = Data(base64Encoded: envelope.dataBase64) else {
                remainingEnvelopes.append(envelope)
                continue
            }
            do {
                try await importSharedReceipt(binaryData, envelope.fileName, envelope.contentType, context)
                importedCount += 1
            } catch {
                remainingEnvelopes.append(envelope)
            }
        }

        if remainingEnvelopes.isEmpty {
            try fileManager.removeItem(at: manifestURL)
        } else {
            let remainingData = try JSONEncoder().encode(remainingEnvelopes)
            try remainingData.write(to: manifestURL, options: .atomic)
        }

        return importedCount
    }
}
