import SwiftUI

struct ReceiptRowView: View {
    let receipt: ReceiptRecord
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }

            RoundedRectangle(cornerRadius: 14)
                .fill(tintColor.opacity(0.16))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: sourceIcon)
                        .font(.title3)
                        .foregroundStyle(tintColor)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(receipt.displayMerchant)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(receipt.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(statusColor)
                }

                HStack {
                    Text(receipt.amount > 0 ? StitchFormatters.currency(amount: receipt.amount, code: receipt.currencyCode) : "Amount missing")
                    Spacer()
                    Text(receipt.purchaseDate.map(StitchFormatters.shortDate.string(from:)) ?? "Date missing")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if receipt.duplicateFlag || receipt.uploadState == .failed {
                    Text(receipt.uploadState == .failed ? receipt.lastUploadError : "Possible duplicate")
                        .font(.caption)
                        .foregroundStyle(receipt.uploadState == .failed ? .red : .orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceIcon: String {
        switch receipt.source {
        case .camera:
            "doc.viewfinder"
        case .photoLibrary:
            "photo.on.rectangle"
        case .files:
            "doc.richtext"
        case .shareSheet:
            "square.and.arrow.down.on.square"
        }
    }

    private var tintColor: Color {
        switch receipt.source {
        case .camera:
            .blue
        case .photoLibrary:
            .green
        case .files:
            .indigo
        case .shareSheet:
            .teal
        }
    }

    private var statusColor: Color {
        switch receipt.status {
        case .needsReview:
            .orange
        case .ready:
            .blue
        case .uploaded:
            .green
        }
    }
}

