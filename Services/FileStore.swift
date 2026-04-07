import Foundation
import UniformTypeIdentifiers
import UIKit

struct StoredReceiptFile {
    let relativePath: String
    let fileName: String
    let contentType: String
}

actor ReceiptFileStore {
    private let fileManager: FileManager
    private let receiptsDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.receiptsDirectoryURL = appSupport.appending(path: "Receipts", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: receiptsDirectoryURL, withIntermediateDirectories: true)
    }

    func persistJPEGImage(_ image: UIImage, suggestedName: String) throws -> StoredReceiptFile {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try persistData(data, suggestedName: suggestedName, fileExtension: "jpg", contentType: UTType.jpeg.safePreferredMIMEType)
    }

    func persistPhotoData(_ data: Data, suggestedName: String, contentType: String = UTType.jpeg.safePreferredMIMEType) throws -> StoredReceiptFile {
        try persistData(data, suggestedName: suggestedName, fileExtension: "jpg", contentType: contentType)
    }

    func persistImportedFile(from sourceURL: URL, suggestedName: String? = nil) throws -> StoredReceiptFile {
        let hasScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let filename = suggestedName ?? sourceURL.lastPathComponent
        let contentType = UTType(filenameExtension: fileExtension)?.safePreferredMIMEType ?? "application/octet-stream"
        let data = try Data(contentsOf: sourceURL)
        return try persistData(data, suggestedName: filename, fileExtension: fileExtension, contentType: contentType)
    }

    func persistSharedData(_ data: Data, fileName: String, contentType: String) throws -> StoredReceiptFile {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.isEmpty ? "bin" : URL(fileURLWithPath: fileName).pathExtension
        return try persistData(data, suggestedName: fileName, fileExtension: fileExtension, contentType: contentType)
    }

    func fileURL(for relativePath: String) -> URL {
        receiptsDirectoryURL.appending(path: relativePath)
    }

    func fileData(for relativePath: String) throws -> Data {
        try Data(contentsOf: fileURL(for: relativePath))
    }

    private func persistData(_ data: Data, suggestedName: String, fileExtension: String, contentType: String) throws -> StoredReceiptFile {
        let baseName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
        let sanitized = baseName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let uniqueName = "\(sanitized)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let destination = receiptsDirectoryURL.appending(path: uniqueName)
        try data.write(to: destination, options: .atomic)
        return StoredReceiptFile(relativePath: uniqueName, fileName: suggestedName, contentType: contentType)
    }
}

