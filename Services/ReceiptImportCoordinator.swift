import Foundation
import SwiftData
import UIKit

@MainActor
final class ReceiptImportCoordinator {
    private let fileStore: ReceiptFileStore
    private let extractionService: ReceiptExtractionService

    init(fileStore: ReceiptFileStore, extractionService: ReceiptExtractionService) {
        self.fileStore = fileStore
        self.extractionService = extractionService
    }

    func importScannedImages(_ images: [UIImage], into context: ModelContext) async throws -> [ReceiptRecord] {
        var imported: [ReceiptRecord] = []

        for (index, image) in images.enumerated() {
            let stored = try await fileStore.persistJPEGImage(image, suggestedName: "scan-\(index + 1).jpg")
            let receipt = try await createReceipt(from: stored, source: .camera, into: context)
            imported.append(receipt)
        }

        try context.save()
        return imported
    }

    func importPhotoData(_ data: Data, suggestedName: String, into context: ModelContext) async throws -> ReceiptRecord {
        let stored = try await fileStore.persistPhotoData(data, suggestedName: suggestedName)
        let receipt = try await createReceipt(from: stored, source: .photoLibrary, into: context)
        try context.save()
        return receipt
    }

    func importFiles(at urls: [URL], source: ReceiptSource, into context: ModelContext) async throws -> [ReceiptRecord] {
        var imported: [ReceiptRecord] = []

        for url in urls {
            let stored = try await fileStore.persistImportedFile(from: url)
            let receipt = try await createReceipt(from: stored, source: source, into: context)
            imported.append(receipt)
        }

        try context.save()
        return imported
    }

    func importSharedData(_ data: Data, fileName: String, contentType: String, into context: ModelContext) async throws -> ReceiptRecord {
        let stored = try await fileStore.persistSharedData(data, fileName: fileName, contentType: contentType)
        let receipt = try await createReceipt(from: stored, source: .shareSheet, into: context)
        try context.save()
        return receipt
    }

    private func createReceipt(from stored: StoredReceiptFile, source: ReceiptSource, into context: ModelContext) async throws -> ReceiptRecord {
        let fileURL = await fileStore.fileURL(for: stored.relativePath)
        let extraction = await extractionService.extract(from: fileURL, fallbackName: stored.fileName)
        let fingerprint = await extractionService.duplicateFingerprint(for: extraction)
        let duplicateFlag = hasDuplicate(fingerprint: fingerprint, in: context)

        let receipt = ReceiptRecord(
            merchant: extraction.merchant,
            amount: extraction.amount ?? 0,
            currencyCode: extraction.currencyCode,
            purchaseDate: extraction.purchaseDate,
            status: status(for: extraction),
            source: source,
            uploadState: .idle,
            fileName: stored.fileName,
            contentType: stored.contentType,
            localRelativePath: stored.relativePath,
            notes: duplicateFlag ? "Possible duplicate detected." : "",
            ocrText: extraction.rawText,
            duplicateFingerprint: fingerprint,
            duplicateFlag: duplicateFlag,
            extractionConfidence: extraction.confidence,
            pageCount: extraction.pageCount
        )

        context.insert(receipt)
        return receipt
    }

    private func hasDuplicate(fingerprint: String, in context: ModelContext) -> Bool {
        guard let receipts = try? context.fetch(FetchDescriptor<ReceiptRecord>()) else {
            return false
        }
        return receipts.contains(where: { $0.duplicateFingerprint == fingerprint && !$0.duplicateFingerprint.isEmpty })
    }

    private func status(for extraction: ExtractedReceiptData) -> ReceiptStatus {
        guard extraction.amount != nil, extraction.purchaseDate != nil, !extraction.merchant.isEmpty else {
            return .needsReview
        }
        return .ready
    }
}

