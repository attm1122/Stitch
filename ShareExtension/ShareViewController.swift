import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let groupIdentifier = "group.com.attm1122.Stitch"
    private let manifestFileName = "pending-shares.json"
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLabel()

        Task {
            await importAttachments()
        }
    }

    private func configureLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = "Saving to Stitch..."

        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @MainActor
    private func importAttachments() async {
        do {
            let envelopes = try await loadEnvelopes()
            try persist(envelopes: envelopes)
            statusLabel.text = "Saved \(envelopes.count) receipt\(envelopes.count == 1 ? "" : "s") to Stitch."
            try await Task.sleep(for: .milliseconds(650))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.text = "Couldn’t save this receipt.\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadEnvelopes() async throws -> [PendingSharedReceiptEnvelope] {
        let itemProviders = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        var envelopes: [PendingSharedReceiptEnvelope] = []

        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                let data = try await provider.dataRepresentation(for: UTType.pdf.identifier)
                let fileName = provider.suggestedName ?? "shared-receipt.pdf"
                envelopes.append(PendingSharedReceiptEnvelope(fileName: fileName, contentType: "application/pdf", dataBase64: data.base64EncodedString()))
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await provider.dataRepresentation(for: UTType.image.identifier)
                let fileName = provider.suggestedName ?? "shared-receipt.jpg"
                let contentType = fileName.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
                envelopes.append(PendingSharedReceiptEnvelope(fileName: fileName, contentType: contentType, dataBase64: data.base64EncodedString()))
            }
        }

        return envelopes
    }

    private func persist(envelopes: [PendingSharedReceiptEnvelope]) throws {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let manifestURL = containerURL.appending(path: manifestFileName)
        let existing: [PendingSharedReceiptEnvelope]

        if let existingData = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([PendingSharedReceiptEnvelope].self, from: existingData) {
            existing = decoded
        } else {
            existing = []
        }

        let merged = existing + envelopes
        let data = try JSONEncoder().encode(merged)
        try data.write(to: manifestURL, options: .atomic)
    }
}

private struct PendingSharedReceiptEnvelope: Codable {
    let fileName: String
    let contentType: String
    let dataBase64: String
}

@MainActor
private extension NSItemProvider {
    func dataRepresentation(for typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
