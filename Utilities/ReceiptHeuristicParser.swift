import Foundation

struct ReceiptHeuristicParser {
    private static let amountRegex = try? NSRegularExpression(
        pattern: #"(?<!\d)(?:USD|EUR|GBP|AUD|CAD|\$|€|£)\s?(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{2}))"#,
        options: [.caseInsensitive]
    )

    private let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    func parse(text: String, fallbackMerchant: String, pageCount: Int) -> ExtractedReceiptData {
        let collapsedText = text.replacingOccurrences(of: "\r", with: "\n")
        let merchant = parseMerchant(from: collapsedText, fallback: fallbackMerchant)
        let amount = parseAmount(from: collapsedText)
        let purchaseDate = parseDate(from: collapsedText)
        let currencyCode = parseCurrency(from: collapsedText)
        let confidence = confidenceScore(merchant: merchant, amount: amount, purchaseDate: purchaseDate)

        return ExtractedReceiptData(
            merchant: merchant,
            amount: amount,
            currencyCode: currencyCode,
            purchaseDate: purchaseDate,
            rawText: collapsedText,
            confidence: confidence,
            pageCount: pageCount
        )
    }

    func duplicateFingerprint(for result: ExtractedReceiptData) -> String {
        let merchant = normalize(result.merchant)
        let amount = result.amount.map { String(format: "%.2f", $0) } ?? "none"
        let day = result.purchaseDate.map { Self.dayOnlyString(from: $0) } ?? "none"
        let textPrefix = normalize(result.rawText).prefix(80)
        return [merchant, amount, day, String(textPrefix)].joined(separator: "|")
    }

    private func parseMerchant(from text: String, fallback: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(10) {
            if line.count < 3 { continue }
            if line.rangeOfCharacter(from: .decimalDigits) != nil && line.filter(\.isLetter).count < 3 { continue }
            if line.localizedCaseInsensitiveContains("tax invoice") { continue }
            if line.localizedCaseInsensitiveContains("receipt") { continue }
            return line
        }

        let fallbackName = URL(fileURLWithPath: fallback).deletingPathExtension().lastPathComponent
        return fallbackName.replacingOccurrences(of: "_", with: " ")
    }

    private func parseAmount(from text: String) -> Double? {
        guard let amountRegex = Self.amountRegex else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = amountRegex.matches(in: text, options: [], range: nsrange)

        let values: [Double] = matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let raw = text[range]
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            return Double(raw)
        }

        return values.sorted().last
    }

    private func parseDate(from text: String) -> Date? {
        if let detectorDate = detectedDate(in: text) {
            return detectorDate
        }

        let candidates = extractDateCandidates(from: text)
        for candidate in candidates {
            if let parsed = parseDateCandidate(candidate) {
                return parsed
            }
        }

        return nil
    }

    private func parseCurrency(from text: String) -> String {
        let uppercased = text.uppercased()
        if uppercased.contains("AUD") { return "AUD" }
        if uppercased.contains("EUR") || uppercased.contains("€") { return "EUR" }
        if uppercased.contains("GBP") || uppercased.contains("£") { return "GBP" }
        if uppercased.contains("CAD") { return "CAD" }
        return "USD"
    }

    private func confidenceScore(merchant: String, amount: Double?, purchaseDate: Date?) -> Double {
        var score = 0.2
        if !merchant.isEmpty { score += 0.3 }
        if amount != nil { score += 0.3 }
        if purchaseDate != nil { score += 0.2 }
        return min(score, 1)
    }

    private func normalize(_ input: String) -> String {
        input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func detectedDate(in text: String) -> Date? {
        guard let dateDetector else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return dateDetector.matches(in: text, options: [], range: nsrange)
            .compactMap(\.date)
            .sorted()
            .first
    }

    private func extractDateCandidates(from text: String) -> [String] {
        let patterns = [
            #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#,
            #"\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b"#,
            #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b"#
        ]

        var results: [String] = []
        let nsText = text as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            results.append(contentsOf: matches.map { nsText.substring(with: $0.range) })
        }

        return results
    }

    private func parseDateCandidate(_ candidate: String) -> Date? {
        let formats = [
            "MM/dd/yyyy",
            "M/d/yyyy",
            "dd/MM/yyyy",
            "d/M/yyyy",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd-MM-yyyy",
            "MMM d yyyy",
            "MMM d, yyyy",
            "MMMM d yyyy",
            "MMMM d, yyyy"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: candidate.replacingOccurrences(of: ",", with: ", ")) {
                return date
            }
            if let date = formatter.date(from: candidate.replacingOccurrences(of: ", ", with: ",")) {
                return date
            }
            if let date = formatter.date(from: candidate) {
                return date
            }
        }

        return nil
    }

    private static func dayOnlyString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
