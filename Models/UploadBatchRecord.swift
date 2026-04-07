import Foundation
import SwiftData

enum UploadBatchState: String, Codable, CaseIterable, Identifiable {
    case queued = "Queued"
    case uploading = "Uploading"
    case partial = "Partial"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }
}

@Model
final class UploadBatchRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var completedAt: Date?
    var stateRawValue: String
    var receiptIdentifiersCSV: String
    var successCount: Int
    var failureCount: Int
    var message: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        completedAt: Date? = nil,
        state: UploadBatchState = .queued,
        receiptIdentifiersCSV: String = "",
        successCount: Int = 0,
        failureCount: Int = 0,
        message: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.stateRawValue = state.rawValue
        self.receiptIdentifiersCSV = receiptIdentifiersCSV
        self.successCount = successCount
        self.failureCount = failureCount
        self.message = message
    }

    var state: UploadBatchState {
        get { UploadBatchState(rawValue: stateRawValue) ?? .queued }
        set { stateRawValue = newValue.rawValue }
    }

    var receiptIdentifiers: [UUID] {
        receiptIdentifiersCSV
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
}
