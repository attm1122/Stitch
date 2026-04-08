import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let groupIdentifier = "group.com.attm1122.Stitch"
    private let manifestFileName = "pending-shares.json"
    private let statusLabel = UILabel()

    private let maxFileSizeBytes: Int = 20 * 1024 * 1024

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
            if envelopes.isEmpty {
                statusLabel.text = "No supported receipt files found.\nPlease share a PDF or image."
                try await Task.sleep(for: .seconds(2))
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
            try persist(envelopes: envelopes)
            statusLabel.text = "Saved \(envelopes.count) receipt\(envelopes.count == 1 ? "" : "s") to Stitch."
            try await Task.sleep(for: .milliseconds(650))
            extensionContext?.completeRequest(returningItems: nil)
        } catch ShareExtensionError.fileTooLarge(let fileName, let sizeMB) {
            statusLabel.text = "'\(fileName)' is too large (\(sizeMB) MB). Stitch supports files up to 20 MB."
            try? await Task.sleep(for: .seconds(3))
            extensionContext?.cancelRequest(withError: ShareExtensionError.fileTooLarge(fileName: fileName, sizeMB: sizeMB))
        } catch {
            statusLabel.text = "Couldn't save this receipt.\n\(error.localizedDescription)"
            try? await Task.sleep(for: .seconds(2))
            extensionContext?.cancelRequest(withError: error)
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
                try checkFileSize(data, fileName: fileName)
                envelopes.append(PendingSharedReceiptEnvelope(
                    fileName: fileName,
                    contentType: "application/pdf",
                    dataBase64: data.base64EncodedString()
                ))
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await provider.dataRepresentation(for: UTType.image.identifier)
                let fileName = provider.suggestedName ?? "shared-receipt.jpg"
                try checkFileSize(data, fileName: fileName)
                let contentType = fileName.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
                envelopes.append(PendingSharedReceiptEnvelope(
                    fileName: fileName,
                    contentType: contentType,
                    dataBase64: data.base64EncodedString()
                ))
            }
        }

        return envelopes
    }

    private func checkFileSize(_ data: Data, fileName: String) throws {
        if data.count > maxFileSizeBytes {
            let sizeMB = Int((Double(data.count) / 1_048_576).rounded())
            throw ShareExtensionError.fileTooLarge(fileName: fileName, sizeMB: sizeMB)
        }
    }

    private func persist(envelopes: [PendingSharedReceiptEnvelope]) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
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

        let combined = existing + envelopes
        let encoded = try JSONEncoder().encode(combined)
        try encoded.write(to: manifestURL, options: .atomic)
    }
}

enum ShareExtensionError: LocalizedError {
    case fileTooLarge(fileName: String, sizeMB: Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let fileName, let sizeMB):
            "'\(fileName)' (\(sizeMB) MB) exceeds the 20 MB limit."
        }
    }
}

struct PendingSharedReceiptEnvelope: Codable {
    let fileName: String
    let contentType: String
    let dataBase64: String
}
