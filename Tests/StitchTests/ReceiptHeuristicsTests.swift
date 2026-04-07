import Testing
@testable import Stitch

struct ReceiptHeuristicsTests {
    @Test
    func parsesMerchantAmountAndDate() {
        let parser = ReceiptHeuristicParser()
        let text = """
        COFFEE REPUBLIC
        TAX INVOICE
        03/14/2026
        TOTAL $18.40
        """

        let result = parser.parse(text: text, fallbackMerchant: "fallback.jpg", pageCount: 1)

        #expect(result.merchant == "COFFEE REPUBLIC")
        #expect(result.amount == 18.40)
        #expect(result.purchaseDate != nil)
    }

    @Test
    func producesStableDuplicateFingerprint() {
        let parser = ReceiptHeuristicParser()
        let text = """
        HOTEL CENTRAL
        2026-02-09
        TOTAL AUD 219.90
        """
        let result = parser.parse(text: text, fallbackMerchant: "hotel.pdf", pageCount: 2)

        let fingerprintA = parser.duplicateFingerprint(for: result)
        let fingerprintB = parser.duplicateFingerprint(for: result)

        #expect(fingerprintA == fingerprintB)
    }
}
