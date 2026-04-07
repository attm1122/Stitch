import Foundation
import PDFKit
import UIKit
import Vision

actor ReceiptExtractionService {
    private let parser = ReceiptHeuristicParser()

    func extract(from fileURL: URL, fallbackName: String) async -> ExtractedReceiptData {
        if fileURL.pathExtension.lowercased() == "pdf" {
            return extractFromPDF(at: fileURL, fallbackName: fallbackName)
        }
        return await extractFromImage(at: fileURL, fallbackName: fallbackName)
    }

    func duplicateFingerprint(for result: ExtractedReceiptData) -> String {
        parser.duplicateFingerprint(for: result)
    }

    private func extractFromPDF(at url: URL, fallbackName: String) -> ExtractedReceiptData {
        guard let document = PDFDocument(url: url) else {
            return parser.parse(text: "", fallbackMerchant: fallbackName, pageCount: 1)
        }

        var collectedText = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex)?.string {
                collectedText.append(page)
                collectedText.append("\n")
            }
        }

        return parser.parse(text: collectedText, fallbackMerchant: fallbackName, pageCount: max(document.pageCount, 1))
    }

    private func extractFromImage(at url: URL, fallbackName: String) async -> ExtractedReceiptData {
        guard let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else {
            return parser.parse(text: "", fallbackMerchant: fallbackName, pageCount: 1)
        }

        let recognizedText = await recognizeText(in: cgImage)
        return parser.parse(text: recognizedText, fallbackMerchant: fallbackName, pageCount: 1)
    }

    private func recognizeText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])
            }
        }
    }
}

