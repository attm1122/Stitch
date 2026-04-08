import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Bindable var receipt: ReceiptRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var amountText: String
    @State private var saveError: String?
    @State private var showingSaveError = false

    init(receipt: ReceiptRecord) {
        self.receipt = receipt
        _amountText = State(initialValue: receipt.amount > 0 ? String(format: "%.2f", receipt.amount) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    TextField("Merchant", text: $receipt.merchant)

                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { receipt.purchaseDate ?? .now },
                            set: { receipt.purchaseDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    Picker("Status", selection: Binding(
                        get: { receipt.status },
                        set: { receipt.status = $0 }
                    )) {
                        ForEach(ReceiptStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }

                Section("Receipt") {
                    LabeledContent("Source", value: receipt.source.rawValue)
                    LabeledContent("Confidence", value: "\(Int(receipt.extractionConfidence * 100))%")
                    LabeledContent("Pages", value: "\(receipt.pageCount)")

                    if receipt.duplicateFlag {
                        Label("This looks like a possible duplicate.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $receipt.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if !receipt.lastUploadError.isEmpty {
                    Section("Upload error") {
                        Text(receipt.lastUploadError)
                            .foregroundStyle(.red)
                    }
                }

                Section("OCR text") {
                    Text(receipt.ocrText.isEmpty ? "No OCR text captured yet." : receipt.ocrText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(receipt.ocrText.isEmpty ? .secondary : .primary)
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
            .alert("Save Failed", isPresented: $showingSaveError, presenting: saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
                Text("Your changes have not been saved. Please try again.")
            }
        }
    }

    private func saveAndDismiss() {
        if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) {
            receipt.amount = amount
        }
        receipt.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }
}
