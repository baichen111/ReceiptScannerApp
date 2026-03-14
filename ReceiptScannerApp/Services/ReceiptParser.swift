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
        "card", "account", "approved", "transaction",
        "phone", "tel", "fax", "www", "http",
        "member", "reward", "points", "loyalty",
    ]

    static func parse(lines: [String]) -> ParsedReceipt {
        var result = ParsedReceipt()

        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if trimmedLines.isEmpty { return result }

        print("[Parser] === Parsing \(trimmedLines.count) lines ===")
        for (i, line) in trimmedLines.enumerated() {
            print("[Parser] [\(i)] \(line)")
        }

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
        print("[Parser] Store: \(result.storeName)")

        // --- Extract date ---
        result.date = extractDate(from: trimmedLines)
        print("[Parser] Date: \(result.date?.description ?? "nil")")

        // --- Process each line for items, tax, total ---
        for line in trimmedLines {
            let lower = line.lowercased()

            guard let price = extractPrice(from: line) else {
                continue
            }

            let itemName = extractItemName(from: line)
            print("[Parser] Price line: '\(line)' -> name='\(itemName)' price=\(price)")

            // Check for total (not subtotal)
            if lower.contains("total") && !lower.contains("subtotal") && !lower.contains("sub total") {
                result.total = price
                print("[Parser]   -> TOTAL")
                continue
            }

            // Check for subtotal
            if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("sub-total") {
                result.subtotal = price
                print("[Parser]   -> SUBTOTAL")
                continue
            }

            // Check for tax
            if lower.contains("tax") || lower.contains("gst") || lower.contains("hst") {
                result.tax = price
                print("[Parser]   -> TAX")
                continue
            }

            // Check if line matches any exclude keyword
            let isExcluded = excludeKeywords.contains { keyword in
                lower.contains(keyword)
            }
            if isExcluded {
                print("[Parser]   -> EXCLUDED (keyword match)")
                continue
            }

            // This is likely a regular item
            if !itemName.isEmpty {
                result.items.append((name: itemName, price: price))
                print("[Parser]   -> ITEM added")
            } else {
                print("[Parser]   -> SKIPPED (empty name)")
            }
        }

        // If no total found, try to sum items
        if result.total == nil && !result.items.isEmpty {
            let itemSum = result.items.reduce(0) { $0 + $1.price }
            result.total = itemSum + (result.tax ?? 0)
        }

        print("[Parser] === Result: \(result.items.count) items, total=\(result.total ?? 0) ===")
        return result
    }

    // MARK: - Helpers

    /// Extract price from a line — tries multiple patterns
    private static func extractPrice(from line: String) -> Double? {
        // Pattern 1: Price at end of line like "MILK 2% 3.99" or "MILK $3.99" or "MILK 3.99 F"
        // Pattern 2: Price with $ anywhere like "$3.99"
        // Pattern 3: Price with comma thousands like "1,234.56"
        let patterns = [
            // Price at end, optionally followed by a single letter (tax code) and spaces
            #"[-]?\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})\s*[A-Za-z]?\s*$"#,
            // Price with $ sign anywhere in line
            #"\$\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#,
            // Simple price at end
            #"(\d+\.\d{2})\s*$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            // Find the LAST match in the line (prices are usually at the end)
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let match = matches.last,
                  let range = Range(match.range(at: 1), in: line) else { continue }
            let priceStr = line[range].replacingOccurrences(of: ",", with: "")
            if let price = Double(priceStr) {
                return price
            }
        }
        return nil
    }

    /// Extract item name by removing the price portion and any surrounding noise
    private static func extractItemName(from line: String) -> String {
        // Remove trailing price patterns (with optional tax code letter)
        let patterns = [
            #"\s*[-]?\$?\s*\d{1,3}(?:,\d{3})*\.\d{2}\s*[A-Za-z]?\s*$"#,
            #"\$\s*\d{1,3}(?:,\d{3})*\.\d{2}"#,
        ]

        var cleaned = line
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Remove leading quantity patterns like "1 x " or "2@ "
        let qtyPattern = #"^\d+\s*[x@]\s*"#
        if let qtyRegex = try? NSRegularExpression(pattern: qtyPattern, options: .caseInsensitive) {
            cleaned = qtyRegex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Remove leading/trailing non-alphanumeric characters
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        cleaned = cleaned.trimmingCharacters(in: .punctuationCharacters)
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        return cleaned
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
            (#"\d{1,2}/\d{1,2}/\d{2}"#, "M/d/yy"),
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
                    // Sanity check: date should be within last 5 years
                    let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    if date > fiveYearsAgo && date < tomorrow {
                        return date
                    }
                }
            }
        }
        return nil
    }
}
