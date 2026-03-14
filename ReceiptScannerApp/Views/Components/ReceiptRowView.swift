import SwiftUI

struct ReceiptRowView: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            // Store icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "bag.fill")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.storeName.isEmpty ? "Unknown Store" : receipt.storeName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(receipt.items.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(String(format: "$%.2f", receipt.total))
                .font(.headline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
