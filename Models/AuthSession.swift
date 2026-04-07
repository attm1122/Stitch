import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let email: String
    let expiresAt: Date?
}

struct ExtractedReceiptData: Equatable {
    let merchant: String
    let amount: Double?
    let currencyCode: String
    let purchaseDate: Date?
    let rawText: String
    let confidence: Double
    let pageCount: Int
}

