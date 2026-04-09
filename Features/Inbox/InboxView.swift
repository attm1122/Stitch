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
    @State private var isShowingOnboarding = false
    @State private var isWorking = false
    @State private var bannerMessage: String?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var importError: String?
    @State private var showingImportError = false

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

                if receipts.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No receipts yet",
                                systemImage: "tray",
                                description: Text("Scan, import, or share receipts into Stitch to start building your upload batch.")
                            )
                            Button("How does Stitch work?") {
                                isShowingOnboarding = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 8)
                    }
                } else if filteredReceipts.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: searchText)
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
                        .onDelete(perform: deleteReceipts)
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
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }

                    if isSelecting && !selectedIDs.isEmpty {
                        Button("Deselect All") {
                            selectedIDs.removeAll()
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }

                    Menu {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("Scan Receipt", systemImage: "doc.viewfinder")
                        }

                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("Import File", systemImage: "doc.richtext")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    if !readyReceipts.isEmpty {
                        Spacer()
                        Button {
                            isShowingUploadQueue = true
                        } label: {
                            Label(
                                "\(uploadCandidates.count) Ready to Upload",
                                systemImage: "arrow.up.to.line"
                            )
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .sheet(item: $selectedReceipt) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingUploadQueue) {
                UploadQueueView(uploadCandidates: uploadCandidates)
            }
            .sheet(isPresented: $isShowingOnboarding) {
                OnboardingView()
            }
            .fullScreenCover(isPresented: $isShowingScanner) {
                DocumentScannerView { images in
                    isShowingScanner = false
                    Task { await importScanned(images) }
                } onCancel: {
                    isShowingScanner = false
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: true
            ) { result in
                Task { await importFiles(result) }
            }
            .onChange(of: photoSelection) { _, newItems in
                Task { await importPhotos(newItems) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await ingestSharedReceipts() }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("Importing...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(alignment: .top) {
                if let bannerMessage {
                    Text(bannerMessage)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Import Failed", isPresented: $showingImportError, presenting: importError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
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

    private func deleteReceipts(at offsets: IndexSet) {
        for index in offsets {
            let receipt = filteredReceipts[index]
            modelContext.delete(receipt)
        }
        do {
            try modelContext.save()
        } catch {
            importError = "Could not delete receipt: \(error.localizedDescription)"
            showingImportError = true
        }
    }

    private func importScanned(_ images: [UIImage]) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await services.importer.importScannedImages(images, into: modelContext)
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isWorking = true
        defer {
            isWorking = false
            photoSelection.removeAll()
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let contentType = item.supportedContentTypes.first ?? .jpeg
            let fileExtension = contentType.preferredFilenameExtension ?? "jpg"
            let baseName = item.itemIdentifier ?? UUID().uuidString
            let name = "\(baseName).\(fileExtension)"
            do {
                _ = try await services.importer.importPhotoData(
                    data,
                    suggestedName: name,
                    contentType: contentType.safePreferredMIMEType,
                    into: modelContext
                )
            } catch {
                importError = error.localizedDescription
                showingImportError = true
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        isWorking = true
        defer { isWorking = false }
        switch result {
        case .success(let urls):
            do {
                _ = try await services.importer.importFiles(at: urls, source: .files, into: modelContext)
            } catch {
                importError = error.localizedDescription
                showingImportError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func ingestSharedReceipts() async {
        do {
            let count = try await services.appGroupInbox.ingestPendingShares(into: modelContext)
            if count > 0 {
                let message = "Added \(count) shared receipt\(count == 1 ? "" : "s")."
                withAnimation(.spring(duration: 0.25)) {
                    bannerMessage = message
                }

                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        guard bannerMessage == message else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            bannerMessage = nil
                        }
                    }
                }
            }
        } catch {
        }
    }
}
