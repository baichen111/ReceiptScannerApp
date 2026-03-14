import SwiftUI

struct ReceiptDetailView: View {
    let receipt: Receipt
    @State private var showRawText = false

    var body: some View {
        List {
            // Receipt image
            if let imageData = receipt.imageData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }
            }

            // Store info
            Section("Store Info") {
                LabeledContent("Store", value: receipt.storeName.isEmpty ? "Unknown" : receipt.storeName)
                LabeledContent("Date", value: receipt.date.formatted(date: .long, time: .omitted))
                LabeledContent("Scanned", value: receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
            }

            // Items
            if !receipt.items.isEmpty {
                Section {
                    ForEach(receipt.items.sorted(by: { $0.name < $1.name })) { item in
                        HStack {
                            Text(item.name)
                                .lineLimit(2)

                            Spacer()

                            if item.quantity > 1 {
                                Text("x\(item.quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(String(format: "$%.2f", item.price))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    HStack {
                        Text("Items")
                        Spacer()
                        Text("\(receipt.items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Totals
            Section("Summary") {
                if let subtotal = receipt.subtotal {
                    HStack {
                        Text("Subtotal")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", subtotal))
                            .monospacedDigit()
                    }
                }

                if let tax = receipt.tax {
                    HStack {
                        Text("Tax")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", tax))
                            .monospacedDigit()
                    }
                }

                HStack {
                    Text("Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "$%.2f", receipt.total))
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }

            // Raw OCR text
            if !receipt.rawText.isEmpty {
                Section {
                    DisclosureGroup("Raw OCR Text") {
                        Text(receipt.rawText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(receipt.storeName.isEmpty ? "Receipt" : receipt.storeName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
