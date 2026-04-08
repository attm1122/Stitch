import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let email: String
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var isExpiringSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }
}

struct ExtractedReceiptData: Equatable {
    let merchant: String
    let amount: Double?
    let currencyCode: String
    let purchaseDate: Date?
    let rawText: String
    let confidence: Double
    let pageCount: Int
    let extractionError: String?

    init(
        merchant: String,
        amount: Double?,
        currencyCode: String,
        purchaseDate: Date?,
        rawText: String,
        confidence: Double,
        pageCount: Int,
        extractionError: String? = nil
    ) {
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.rawText = rawText
        self.confidence = confidence
        self.pageCount = pageCount
        self.extractionError = extractionError
    }
}
