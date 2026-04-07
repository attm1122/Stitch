import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct InboxView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: [SortDescriptor(\ReceiptRecord.createdAt, order: .reverse)]) private var receipts: [ReceiptRecord]

    @State private var filter: InboxFilter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var selectedReceipt: ReceiptRecord?
    @State private var isShowingScanner = false
    @State private var isShowingFileImporter = false
    @State private var isShowingUploadQueue = false
    @State private var isShowingSettings = false
    @State private var isWorking = false
    @State private var bannerMessage: String?
    @State private var photoSelection: [PhotosPickerItem] = []

    private var filteredReceipts: [ReceiptRecord] {
        receipts.filter { receipt in
            let matchesFilter = filter.matches(receipt)
            let matchesSearch: Bool

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let haystack = [
                    receipt.displayMerchant,
                    receipt.fileName,
                    receipt.ocrText,
                    String(receipt.amount),
                    receipt.purchaseDate.map(StitchFormatters.shortDate.string(from:)) ?? ""
                ].joined(separator: " ").lowercased()
                matchesSearch = haystack.contains(searchText.lowercased())
            }

            return matchesFilter && matchesSearch
        }
    }

    private var readyReceipts: [ReceiptRecord] {
        receipts.filter(\.isReadyForUpload)
    }

    private var uploadCandidates: [ReceiptRecord] {
        let selected = receipts.filter { selectedIDs.contains($0.id) && $0.isReadyForUpload }
        return selected.isEmpty ? readyReceipts : selected
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(InboxFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if filteredReceipts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No receipts yet",
                            systemImage: "tray",
                            description: Text("Scan, import, or share receipts into Stitch to start building your upload batch.")
                        )
                    }
                } else {
                    Section {
                        ForEach(filteredReceipts) { receipt in
                            Button {
                                handleTap(on: receipt)
                            } label: {
                                ReceiptRowView(
                                    receipt: receipt,
                                    isSelecting: isSelecting,
                                    isSelected: selectedIDs.contains(receipt.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Receipt Inbox")
            .searchable(text: $searchText, prompt: "Merchant, amount, or date")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(isSelecting ? "Done" : "Select") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting {
                                selectedIDs.removeAll()
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingUploadQueue = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let bannerMessage {
                        Text(bannerMessage)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(spacing: 10) {
                        Button {
                            guard VNDocumentCameraViewController.isSupported else {
                                bannerMessage = "The document scanner is only available on supported devices."
                                return
                            }
                            isShowingScanner = true
                        } label: {
                            CaptureActionLabel(title: "Scan", systemImage: "doc.viewfinder")
                        }

                        PhotosPicker(selection: $photoSelection, maxSelectionCount: 10, matching: .images) {
                            CaptureActionLabel(title: "Photos", systemImage: "photo.stack")
                        }

                        Button {
                            isShowingFileImporter = true
                        } label: {
                            CaptureActionLabel(title: "Files", systemImage: "folder")
                        }

                        Button {
                            Task {
                                await uploadReadyReceipts()
                            }
                        } label: {
                            CaptureActionLabel(
                                title: uploadCandidates.isEmpty ? "Upload" : "Upload \(uploadCandidates.count)",
                                systemImage: "arrow.up.circle.fill"
                            )
                        }
                        .disabled(uploadCandidates.isEmpty || sessionStore.expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
            .task {
                await ingestSharedReceipts()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await ingestSharedReceipts()
                }
            }
            .onChange(of: photoSelection) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await importPhotoItems(newItems)
                    photoSelection = []
                }
            }
            .sheet(item: $selectedReceipt) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
            .sheet(isPresented: $isShowingScanner) {
                DocumentScannerView(
                    onComplete: { images in
                        isShowingScanner = false
                        Task {
                            await importScans(images)
                        }
                    },
                    onCancel: {
                        isShowingScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingUploadQueue) {
                UploadQueueView()
                    .environmentObject(services)
                    .environmentObject(sessionStore)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environmentObject(services)
                    .environmentObject(sessionStore)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await importFiles(urls)
                    }
                case .failure(let error):
                    bannerMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleTap(on receipt: ReceiptRecord) {
        if isSelecting {
            if selectedIDs.contains(receipt.id) {
                selectedIDs.remove(receipt.id)
            } else {
                selectedIDs.insert(receipt.id)
            }
        } else {
            selectedReceipt = receipt
        }
    }

}

private struct CaptureActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension InboxView {
    func importScans(_ images: [UIImage]) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let imported = try await services.importer.importScannedImages(images, into: modelContext)
            bannerMessage = "Imported \(imported.count) scanned receipt\(imported.count == 1 ? "" : "s")."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func importPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            var count = 0
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let fileName = item.itemIdentifier ?? "photo-\(count + 1).jpg"
                _ = try await services.importer.importPhotoData(data, suggestedName: fileName, into: modelContext)
                count += 1
            }
            bannerMessage = "Imported \(count) photo receipt\(count == 1 ? "" : "s")."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let imported = try await services.importer.importFiles(at: urls, source: .files, into: modelContext)
            bannerMessage = "Imported \(imported.count) file receipt\(imported.count == 1 ? "" : "s")."
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func uploadReadyReceipts() async {
        guard !uploadCandidates.isEmpty else {
            bannerMessage = "No ready receipts available."
            return
        }

        let email = sessionStore.expensifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            bannerMessage = "Add an Expensify destination email in Settings first."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let batch = await services.uploadService.upload(
            receipts: uploadCandidates,
            expensifyEmail: email,
            session: sessionStore.session,
            in: modelContext
        )

        bannerMessage = batch.message
        if isSelecting {
            selectedIDs.removeAll()
        }
    }

    func ingestSharedReceipts() async {
        do {
            let imported = try await services.appGroupInbox.ingestPendingShares(into: modelContext)
            if imported > 0 {
                bannerMessage = "Imported \(imported) receipt\(imported == 1 ? "" : "s") from the Share Sheet."
            }
        } catch {
            bannerMessage = error.localizedDescription
        }
    }
}
