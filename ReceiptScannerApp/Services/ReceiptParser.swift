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
        "net amount", "rounding",
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
            if extractLastPrice(from: line) != nil {
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

            guard let price = extractLastPrice(from: line) else {
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
            if !itemName.isEmpty && itemName.count >= 2 {
                result.items.append((name: itemName, price: price))
                print("[Parser]   -> ITEM added")
            } else {
                print("[Parser]   -> SKIPPED (name too short: '\(itemName)')")
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

    /// Find ALL prices in a line, return the LAST one (usually the line total)
    private static func extractLastPrice(from line: String) -> Double? {
        let pattern = #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))

        // Return the last price found (line total, not unit price)
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: line) else { return nil }
        let priceStr = line[range].replacingOccurrences(of: ",", with: "")
        return Double(priceStr)
    }

    /// Extract item name: find the longest alphabetic substring in the line
    private static func extractItemName(from line: String) -> String {
        // Strategy: Extract all the "word" segments (letters, spaces, hyphens, common punctuation)
        // that sit between numeric/price segments.

        var cleaned = line

        // Step 1: Remove the last price (line total) from the end
        let trailingPrice = #"\s*\$?\s*\d{1,3}(?:,\d{3})*\.\d{2}\s*[A-Za-z]?\s*$"#
        if let regex = try? NSRegularExpression(pattern: trailingPrice) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 2: Remove leading item numbers like "1." or "12." or "1 "
        let leadingNum = #"^\d{1,3}[.\s]\s*"#
        if let regex = try? NSRegularExpression(pattern: leadingNum) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 3: Remove leading quantity like "2 x 13.80" or "4 x 0.06"
        let leadingQty = #"^\d+\s*[xX@]\s*\d*\.?\d*\s*"#
        if let regex = try? NSRegularExpression(pattern: leadingQty) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 4: Remove barcode/product codes (8+ digit numbers)
        let barcode = #"\b\d{8,}\b"#
        if let regex = try? NSRegularExpression(pattern: barcode) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 5: Remove remaining standalone prices that aren't part of a word
        let midPrice = #"\b\d{1,3}\.\d{2}\b"#
        if let regex = try? NSRegularExpression(pattern: midPrice) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 6: Remove "Qty" info
        let qtyInfo = #"(?i)\bqty\s*:?\s*\d+"#
        if let regex = try? NSRegularExpression(pattern: qtyInfo) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Step 7: Extract the best text segment — find the longest run of letters/spaces
        // This handles cases where the name is embedded between numbers
        let wordPattern = #"[A-Za-z][A-Za-z0-9\s/&%'.-]{1,}"#
        if let regex = try? NSRegularExpression(pattern: wordPattern) {
            let matches = regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            // Pick the longest match as the item name
            var bestMatch = ""
            for match in matches {
                if let range = Range(match.range, in: cleaned) {
                    let candidate = String(cleaned[range]).trimmingCharacters(in: .whitespaces)
                    if candidate.count > bestMatch.count {
                        bestMatch = candidate
                    }
                }
            }
            if !bestMatch.isEmpty {
                return bestMatch.trimmingCharacters(in: .punctuationCharacters)
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Fallback: just trim everything
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
