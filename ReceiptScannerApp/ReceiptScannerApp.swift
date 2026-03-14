import SwiftUI
import SwiftData

@main
struct ReceiptScannerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [Receipt.self, ReceiptItem.self])
    }
}
