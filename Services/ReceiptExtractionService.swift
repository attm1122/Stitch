import Foundation
import PDFKit
import UIKit
import Vision

enum ExtractionError: LocalizedError {
    case invalidFile
    case ocrFailed(Error)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "The receipt file could not be read."
        case .ocrFailed(let underlying):
            "Text recognition failed: \(underlying.localizedDescription)"
        case .unsupportedFormat:
            "This file format is not supported."
        }
    }
}

actor ReceiptExtractionService {
    private let parser = ReceiptHeuristicParser()

    func extract(from fileURL: URL, fallbackName: String) async throws -> ExtractedReceiptData {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return try extractFromPDF(at: fileURL, fallbackName: fallbackName)
        case "jpg", "jpeg", "png", "heic", "tiff", "bmp":
            return try await extractFromImage(at: fileURL, fallbackName: fallbackName)
        default:
            if let data = try? Data(contentsOf: fileURL), let _ = UIImage(data: data) {
                return try await extractFromImage(at: fileURL, fallbackName: fallbackName)
            }
            return parser.parse(text: "", fallbackMerchant: fallbackName, pageCount: 1)
        }
    }

    func duplicateFingerprint(for result: ExtractedReceiptData) -> String {
        parser.duplicateFingerprint(for: result)
    }

    private func extractFromPDF(at url: URL, fallbackName: String) throws -> ExtractedReceiptData {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.invalidFile
        }

        var collectedText = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex),
               let pageText = page.string {
                collectedText += pageText + "\n"
            }
        }

        return parser.parse(text: collectedText, fallbackMerchant: fallbackName, pageCount: document.pageCount)
    }

    private func extractFromImage(at url: URL, fallbackName: String) async throws -> ExtractedReceiptData {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            throw ExtractionError.invalidFile
        }

        let recognizedText = try await recognizeText(in: cgImage)
        return parser.parse(text: recognizedText, fallbackMerchant: fallbackName, pageCount: 1)
    }

    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ExtractionError.ocrFailed(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: ExtractionError.ocrFailed(error))
                }
            }
        }
    }
}
