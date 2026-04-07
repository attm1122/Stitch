import UniformTypeIdentifiers

extension UTType {
    var safePreferredMIMEType: String {
        preferredMIMEType ?? "application/octet-stream"
    }
}

