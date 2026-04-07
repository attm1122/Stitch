import Foundation
import SwiftData

enum ReceiptStatus: String, CaseIterable, Codable, Identifiable {
    case needsReview = "Needs Review"
    case ready = "Ready"
    case uploaded = "Uploaded"

    var id: String { rawValue }
}

enum ReceiptSource: String, CaseIterable, Codable, Identifiable {
    case camera = "Camera"
    case photoLibrary = "Photos"
    case files = "Files"
    case shareSheet = "Share Sheet"

    var id: String { rawValue }
}

enum UploadState: String, CaseIterable, Codable, Identifiable {
    case idle = "Idle"
    case uploading = "Uploading"
    case uploaded = "Uploaded"
    case failed = "Failed"

    var id: String { rawValue }
}

enum InboxFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case ready = "Ready"
    case uploaded = "Uploaded"

    var id: String { rawValue }

    func matches(_ receipt: ReceiptRecord) -> Bool {
        switch self {
        case .all:
            true
        case .needsReview:
            receipt.status == .needsReview
        case .ready:
            receipt.status == .ready
        case .uploaded:
            receipt.status == .uploaded
        }
    }
}

@Model
final class ReceiptRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var merchant: String
    var amount: Double
    var currencyCode: String
    var purchaseDate: Date?
    var statusRawValue: String
    var sourceRawValue: String
    var uploadStateRawValue: String
    var fileName: String
    var contentType: String
    var localRelativePath: String
    var notes: String
    var ocrText: String
    var duplicateFingerprint: String
    var duplicateFlag: Bool
    var extractionConfidence: Double
    var pageCount: Int
    var lastUploadAttemptAt: Date?
    var lastUploadError: String
    var uploadedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        merchant: String = "",
        amount: Double = 0,
        currencyCode: String = "USD",
        purchaseDate: Date? = nil,
        status: ReceiptStatus = .needsReview,
        source: ReceiptSource,
        uploadState: UploadState = .idle,
        fileName: String,
        contentType: String,
        localRelativePath: String,
        notes: String = "",
        ocrText: String = "",
        duplicateFingerprint: String = "",
        duplicateFlag: Bool = false,
        extractionConfidence: Double = 0,
        pageCount: Int = 1,
        lastUploadAttemptAt: Date? = nil,
        lastUploadError: String = "",
        uploadedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.statusRawValue = status.rawValue
        self.sourceRawValue = source.rawValue
        self.uploadStateRawValue = uploadState.rawValue
        self.fileName = fileName
        self.contentType = contentType
        self.localRelativePath = localRelativePath
        self.notes = notes
        self.ocrText = ocrText
        self.duplicateFingerprint = duplicateFingerprint
        self.duplicateFlag = duplicateFlag
        self.extractionConfidence = extractionConfidence
        self.pageCount = pageCount
        self.lastUploadAttemptAt = lastUploadAttemptAt
        self.lastUploadError = lastUploadError
        self.uploadedAt = uploadedAt
    }

    var status: ReceiptStatus {
        get { ReceiptStatus(rawValue: statusRawValue) ?? .needsReview }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var source: ReceiptSource {
        get { ReceiptSource(rawValue: sourceRawValue) ?? .files }
        set { sourceRawValue = newValue.rawValue }
    }

    var uploadState: UploadState {
        get { UploadState(rawValue: uploadStateRawValue) ?? .idle }
        set {
            uploadStateRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var displayMerchant: String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fileName : merchant
    }

    var isReadyForUpload: Bool {
        status == .ready && uploadState != .uploaded
    }
}
