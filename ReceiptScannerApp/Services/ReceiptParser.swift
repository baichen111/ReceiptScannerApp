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
        "net amount", "rounding", "purchased",
        "saving", "diners", "contactless",
        "batch", "approval", "terminal", "merc id",
        "exclude", "non gst",
    ]

    // Lines that are just supplementary info (quantity breakdowns, barcodes)
    private static func isSupplementaryLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        // Quantity breakdown: "2 x 13.80" or "2 × 1.40" or "4 x 0.05"
        if let _ = try? NSRegularExpression(pattern: #"^\d+\s*[x×@]\s*\d"#, options: .caseInsensitive),
           lower.range(of: #"^\d+\s*[x×@]\s*\d"#, options: .regularExpression, range: nil, locale: nil) != nil {
            return true
        }
        // Barcode: line is mostly digits (8+ digits)
        if let _ = line.range(of: #"^\d{8,}$"#, options: .regularExpression) {
            return true
        }
        // "2 for $X.XX" discount line
        if lower.contains("for $") || lower.contains("for$") {
            return true
        }
        // PWP Discount or similar
        if lower.contains("discount") || lower.contains("pwp") {
            return true
        }
        // Line starting with "-" (discount amount)
        if line.hasPrefix("-") || line.hasPrefix("- ") {
            return true
        }
        // Stars or dots
        if line.allSatisfy({ $0 == "*" || $0 == "." || $0 == " " }) {
            return true
        }
        return false
    }

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

        // --- Multi-line parsing ---
        // Strategy: Item name is on one line, price is on the next line (or same line).
        // Walk through lines. When we find a price-only line, look back for the item name.

        var i = 0
        var foundTotalSection = false

        while i < trimmedLines.count {
            let line = trimmedLines[i]
            let lower = line.lowercased()

            // Skip supplementary lines
            if isSupplementaryLine(line) {
                print("[Parser] [\(i)] SKIP supplementary: \(line)")
                i += 1
                continue
            }

            // Check for total section markers
            if lower.contains("total amount") || (lower.contains("total") && !lower.contains("subtotal")) {
                foundTotalSection = true
            }

            // Check if this line has a price
            let price = extractPrice(from: line)

            // Check for known keywords
            if let p = price {
                if lower.contains("total") && !lower.contains("subtotal") && !lower.contains("sub total") {
                    result.total = p
                    print("[Parser] [\(i)] TOTAL: \(p)")
                    i += 1
                    continue
                }
                if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("sub-total") {
                    result.subtotal = p
                    print("[Parser] [\(i)] SUBTOTAL: \(p)")
                    i += 1
                    continue
                }
                if lower.contains("tax") || lower.contains("gst") || lower.contains("hst") {
                    result.tax = p
                    print("[Parser] [\(i)] TAX: \(p)")
                    i += 1
                    continue
                }
            }

            // Skip lines after total section (payment details, etc.)
            if foundTotalSection {
                print("[Parser] [\(i)] SKIP post-total: \(line)")
                i += 1
                continue
            }

            // Check if excluded
            let isExcluded = excludeKeywords.contains { lower.contains($0) }
            if isExcluded {
                print("[Parser] [\(i)] EXCLUDED: \(line)")
                i += 1
                continue
            }

            // --- Item detection ---
            let hasPrice = price != nil
            let nameFromLine = extractItemName(from: line)
            let isNameLine = !nameFromLine.isEmpty && nameFromLine.count >= 3

            if hasPrice && isNameLine {
                // Name and price on the same line
                result.items.append((name: nameFromLine, price: price!))
                print("[Parser] [\(i)] ITEM (same line): '\(nameFromLine)' = \(price!)")
                i += 1
                continue
            }

            if isNameLine && !hasPrice {
                // This is a name-only line. Look ahead for the price.
                var priceVal: Double? = nil
                var skip = 1
                while i + skip < trimmedLines.count {
                    let nextLine = trimmedLines[i + skip]
                    if isSupplementaryLine(nextLine) {
                        skip += 1
                        continue
                    }
                    if let p = extractPrice(from: nextLine), !hasLetters(nextLine) {
                        priceVal = p
                        break
                    }
                    break // Next line has text, not our price
                }

                if let p = priceVal {
                    result.items.append((name: nameFromLine, price: p))
                    print("[Parser] [\(i)] ITEM (name + price below): '\(nameFromLine)' = \(p)")
                    i += skip + 1 // Skip past the price line
                    continue
                } else {
                    print("[Parser] [\(i)] NAME without price: '\(nameFromLine)'")
                }
            }

            if hasPrice && !isNameLine {
                // Price-only line. Look back for a name.
                var nameVal: String? = nil
                var j = i - 1
                while j >= 0 {
                    let prevLine = trimmedLines[j]
                    if isSupplementaryLine(prevLine) {
                        j -= 1
                        continue
                    }
                    let prevName = extractItemName(from: prevLine)
                    if prevName.count >= 3 && extractPrice(from: prevLine) == nil {
                        nameVal = prevName
                    }
                    break
                }

                if let name = nameVal {
                    // Check this wasn't already added
                    let alreadyAdded = result.items.contains { $0.name == name }
                    if !alreadyAdded {
                        result.items.append((name: name, price: price!))
                        print("[Parser] [\(i)] ITEM (price + name above): '\(name)' = \(price!)")
                    } else {
                        print("[Parser] [\(i)] SKIP duplicate: '\(name)'")
                    }
                } else {
                    print("[Parser] [\(i)] PRICE without name: \(price!)")
                }
            }

            i += 1
        }

        // If no total found, try to use $207.63-style line
        if result.total == nil {
            for line in trimmedLines.reversed() {
                if line.hasPrefix("$"), let p = extractPrice(from: line), p > 50 {
                    result.total = p
                    break
                }
            }
        }

        print("[Parser] === Result: \(result.items.count) items, total=\(result.total ?? 0) ===")
        for item in result.items {
            print("[Parser]   \(item.name): \(item.price)")
        }
        return result
    }

    // MARK: - Helpers

    /// Check if a string contains any letters
    private static func hasLetters(_ str: String) -> Bool {
        str.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Extract price from a line (finds the last decimal number)
    private static func extractPrice(from line: String) -> Double? {
        let pattern = #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: line) else { return nil }
        let priceStr = line[range].replacingOccurrences(of: ",", with: "")
        return Double(priceStr)
    }

    /// Extract item name from a line by removing numbers, prices, and line prefixes
    private static func extractItemName(from line: String) -> String {
        var cleaned = line

        // Remove leading item number: "5." or "23." or "2. #"
        if let regex = try? NSRegularExpression(pattern: #"^\d{1,3}\.?\s*#?\s*"#) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        // Remove all prices
        if let regex = try? NSRegularExpression(pattern: #"\$?\s*\d{1,3}(?:,\d{3})*\.\d{2}"#) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        // Remove barcodes (8+ digits)
        if let regex = try? NSRegularExpression(pattern: #"\b\d{8,}\b"#) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        // Remove quantity patterns "2 x" or "4 X"
        if let regex = try? NSRegularExpression(pattern: #"\d+\s*[x×@]\s*"#, options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".-#*"))
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    /// Try to find a date in the OCR lines
    private static func extractDate(from lines: [String]) -> Date? {
        let datePatterns: [(pattern: String, format: String)] = [
            (#"\d{2}/\d{2}/\d{4}"#, "dd/MM/yyyy"),
            (#"\d{2}/\d{2}/\d{4}"#, "MM/dd/yyyy"),
            (#"\d{2}-\d{2}-\d{4}"#, "dd-MM-yyyy"),
            (#"\d{4}/\d{2}/\d{2}"#, "yyyy/MM/dd"),
            (#"\d{4}-\d{2}-\d{2}"#, "yyyy-MM-dd"),
            (#"\d{2}/\d{2}/\d{2}"#, "dd/MM/yy"),
            (#"\d{1,2}/\d{1,2}/\d{4}"#, "d/M/yyyy"),
            // Sheng Siong format: 13/03/2026 or 13.03/2026
            (#"\d{2}\.\d{2}/\d{4}"#, "dd.MM/yyyy"),
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
