import Foundation

struct ParsedReceipt {
    var storeName: String = ""
    var date: Date?
    var items: [(name: String, price: Double)] = []
    var subtotal: Double?
    var tax: Double?
    var total: Double?
}

struct ReceiptParser {

    // Keywords that indicate a line is NOT a regular item
    private static let excludeKeywords: [String] = [
        "subtotal", "sub total", "sub-total",
        "total", "tax", "gst", "hst", "pst",
        "cash", "credit", "debit", "visa", "mastercard", "amex",
        "change", "balance", "tender", "payment",
        "discount", "savings", "coupon",
        "thank you", "welcome", "receipt",
        "card", "account", "approved",
    ]

    static func parse(lines: [String]) -> ParsedReceipt {
        var result = ParsedReceipt()

        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if trimmedLines.isEmpty { return result }

        // --- Extract store name (first lines before any price appears) ---
        var storeLines: [String] = []
        for line in trimmedLines {
            if extractPrice(from: line) != nil {
                break
            }
            storeLines.append(line)
            if storeLines.count >= 3 { break }
        }
        result.storeName = storeLines.prefix(2).joined(separator: " ")

        // --- Extract date ---
        result.date = extractDate(from: trimmedLines)

        // --- Process each line for items, tax, total ---
        for line in trimmedLines {
            let lower = line.lowercased()

            guard let price = extractPrice(from: line) else { continue }

            // Check for total (not subtotal)
            if lower.contains("total") && !lower.contains("subtotal") && !lower.contains("sub total") {
                result.total = price
                continue
            }

            // Check for subtotal
            if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("sub-total") {
                result.subtotal = price
                continue
            }

            // Check for tax
            if lower.contains("tax") || lower.contains("gst") || lower.contains("hst") {
                result.tax = price
                continue
            }

            // Check if line matches any exclude keyword
            let isExcluded = excludeKeywords.contains { keyword in
                lower.contains(keyword)
            }
            if isExcluded { continue }

            // This is likely a regular item
            let itemName = extractItemName(from: line)
            if !itemName.isEmpty {
                result.items.append((name: itemName, price: price))
            }
        }

        // If no total found, try to sum items
        if result.total == nil && !result.items.isEmpty {
            let itemSum = result.items.reduce(0) { $0 + $1.price }
            result.total = itemSum + (result.tax ?? 0)
        }

        return result
    }

    // MARK: - Helpers

    /// Extract price from end of line (e.g., "MILK 2% 3.99" -> 3.99)
    private static func extractPrice(from line: String) -> Double? {
        // Match price pattern at end of line: digits.digits, optionally preceded by $ or -
        let pattern = #"[-]?\$?\s*(\d+\.\d{2})\s*[A-Za-z]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[range])
    }

    /// Extract item name by removing the price portion
    private static func extractItemName(from line: String) -> String {
        // Remove trailing price and any trailing letter codes (tax indicators like T, F, etc.)
        let pattern = #"\s*[-]?\$?\s*\d+\.\d{2}\s*[A-Za-z]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let cleaned = regex.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: ""
        )
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Try to find a date in the OCR lines
    private static func extractDate(from lines: [String]) -> Date? {
        let datePatterns: [(pattern: String, format: String)] = [
            (#"\d{2}/\d{2}/\d{4}"#, "MM/dd/yyyy"),
            (#"\d{2}-\d{2}-\d{4}"#, "MM-dd-yyyy"),
            (#"\d{4}/\d{2}/\d{2}"#, "yyyy/MM/dd"),
            (#"\d{4}-\d{2}-\d{2}"#, "yyyy-MM-dd"),
            (#"\d{2}/\d{2}/\d{2}"#, "MM/dd/yy"),
            (#"\d{1,2}/\d{1,2}/\d{4}"#, "M/d/yyyy"),
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for line in lines {
            for (pattern, format) in datePatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range, in: line) else { continue }

                let dateStr = String(line[range])
                formatter.dateFormat = format
                if let date = formatter.date(from: dateStr) {
                    // Sanity check: date should be within last 2 years
                    let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
                    if date > twoYearsAgo && date <= Date() {
                        return date
                    }
                }
            }
        }
        return nil
    }
}
