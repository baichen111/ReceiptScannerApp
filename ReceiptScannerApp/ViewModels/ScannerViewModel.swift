import SwiftUI
import SwiftData

@Observable
class ScannerViewModel {
    enum ScanState {
        case camera
        case processing
        case review
        case error(String)
    }

    var state: ScanState = .camera
    var capturedImage: UIImage?
    var parsedReceipt: ParsedReceipt?
    var ocrLines: [String] = []

    // Editable fields for review
    var editStoreName: String = ""
    var editDate: Date = Date()
    var editTotal: String = ""
    var editTax: String = ""
    var editItems: [(name: String, price: String)] = []

    func processImage(_ image: UIImage) async {
        state = .processing
        capturedImage = image

        do {
            ocrLines = try await OCRService.recognizeText(in: image)
            parsedReceipt = ReceiptParser.parse(lines: ocrLines)
            populateEditFields()
            state = .review
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func populateEditFields() {
        guard let parsed = parsedReceipt else { return }
        editStoreName = parsed.storeName
        editDate = parsed.date ?? Date()
        editTotal = parsed.total.map { String(format: "%.2f", $0) } ?? ""
        editTax = parsed.tax.map { String(format: "%.2f", $0) } ?? ""
        editItems = parsed.items.map { (name: $0.name, price: String(format: "%.2f", $0.price)) }
    }

    func addItem() {
        editItems.append((name: "", price: ""))
    }

    func removeItem(at index: Int) {
        guard index < editItems.count else { return }
        editItems.remove(at: index)
    }

    func save(in context: ModelContext) {
        let total = Double(editTotal) ?? 0
        let receipt = Receipt(
            storeName: editStoreName,
            date: editDate,
            total: total,
            rawText: ocrLines.joined(separator: "\n")
        )
        receipt.tax = Double(editTax)
        receipt.imageData = capturedImage?.jpegData(compressionQuality: 0.7)

        // Calculate subtotal from items
        var itemTotal = 0.0
        for item in editItems {
            let price = Double(item.price) ?? 0
            if !item.name.isEmpty {
                let receiptItem = ReceiptItem(name: item.name, price: price)
                receipt.items.append(receiptItem)
                itemTotal += price
            }
        }
        receipt.subtotal = itemTotal

        context.insert(receipt)
    }

    func reset() {
        state = .camera
        capturedImage = nil
        parsedReceipt = nil
        ocrLines = []
        editStoreName = ""
        editDate = Date()
        editTotal = ""
        editTax = ""
        editItems = []
    }
}
