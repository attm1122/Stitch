import SwiftData
import SwiftUI

@main
struct StitchApp: App {
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .environmentObject(services.sessionStore)
                .onOpenURL { url in
                    Task {
                        await services.sessionStore.handleIncoming(url: url)
                    }
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ReceiptRecord.self,
            UploadBatchRecord.self,
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

