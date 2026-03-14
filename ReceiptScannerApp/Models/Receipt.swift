import Foundation
import SwiftData

@Model
final class Receipt {
    var id: UUID
    var storeName: String
    var date: Date
    var subtotal: Double?
    var tax: Double?
    var total: Double
    var rawText: String
    @Attribute(.externalStorage)
    var imageData: Data?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ReceiptItem.receipt)
    var items: [ReceiptItem]

    init(storeName: String, date: Date, total: Double, rawText: String) {
        self.id = UUID()
        self.storeName = storeName
        self.date = date
        self.total = total
        self.rawText = rawText
        self.createdAt = Date()
        self.items = []
    }
}
