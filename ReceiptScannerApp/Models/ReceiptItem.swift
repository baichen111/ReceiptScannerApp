import Foundation
import SwiftData

@Model
final class ReceiptItem {
    var id: UUID
    var name: String
    var price: Double
    var quantity: Int

    var receipt: Receipt?

    init(name: String, price: Double, quantity: Int = 1) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}
