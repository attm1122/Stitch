import Foundation

@MainActor
final class AppServices: ObservableObject {
    let configuration: BackendConfiguration
    let sessionStore: SessionStore
    let importer: ReceiptImportCoordinator
    let appGroupInbox: AppGroupInboxService
    let uploadService: UploadService

    init(configuration: BackendConfiguration = .current) {
        self.configuration = configuration
        let authService = SupabaseAuthService(configuration: configuration)
        let keychain = KeychainStore()
        let sessionStore = SessionStore(authService: authService, configuration: configuration, keychain: keychain)
        let fileStore = ReceiptFileStore()
        let extractionService = ReceiptExtractionService()
        let importer = ReceiptImportCoordinator(fileStore: fileStore, extractionService: extractionService)

        self.sessionStore = sessionStore
        self.importer = importer
        self.appGroupInbox = AppGroupInboxService(importer: importer)
        self.uploadService = UploadService(configuration: configuration, fileStore: fileStore)
    }
}
