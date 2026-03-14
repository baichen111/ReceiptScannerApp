import UIKit
import Vision

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .recognitionFailed(let msg):
            return "Text recognition failed: \(msg)"
        }
    }
}

struct OCRService {
    static func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // Map UIImage orientation to CGImagePropertyOrientation for Vision
        let orientation = cgOrientation(from: image.imageOrientation)
        print("[OCR] Image size: \(image.size), orientation: \(image.imageOrientation.rawValue) -> cg: \(orientation.rawValue)")

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []

                // Extract text with bounding box info
                struct TextBlock {
                    let text: String
                    let minX: CGFloat  // Left edge (0 = left, 1 = right)
                    let midY: CGFloat  // Vertical center (0 = bottom, 1 = top in Vision coords)
                    let height: CGFloat
                }

                let blocks: [TextBlock] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let box = obs.boundingBox
                    return TextBlock(
                        text: candidate.string,
                        minX: box.origin.x,
                        midY: box.origin.y + box.height / 2,
                        height: box.height
                    )
                }

                print("[OCR] Recognized \(blocks.count) text blocks")
                for (i, b) in blocks.enumerated() {
                    print("[OCR] raw [\(i)] x=\(String(format: "%.3f", b.minX)) y=\(String(format: "%.3f", b.midY)) h=\(String(format: "%.3f", b.height)) '\(b.text)'")
                }

                // Group blocks into rows by similar Y position
                // Two blocks are on the same row if their Y centers are within half
                // the average text height of each other
                let avgHeight = blocks.isEmpty ? 0.01 : blocks.map(\.height).reduce(0, +) / CGFloat(blocks.count)
                let yThreshold = avgHeight * 0.6

                // Sort by Y descending (top of receipt first in Vision coords)
                let sortedBlocks = blocks.sorted { $0.midY > $1.midY }

                var rows: [[TextBlock]] = []
                for block in sortedBlocks {
                    // Try to add to existing row
                    var added = false
                    for ri in rows.indices {
                        let rowY = rows[ri].map(\.midY).reduce(0, +) / CGFloat(rows[ri].count)
                        if abs(block.midY - rowY) < yThreshold {
                            rows[ri].append(block)
                            added = true
                            break
                        }
                    }
                    if !added {
                        rows.append([block])
                    }
                }

                // Sort rows top-to-bottom (highest Y first)
                rows.sort { row1, row2 in
                    let y1 = row1.map(\.midY).reduce(0, +) / CGFloat(row1.count)
                    let y2 = row2.map(\.midY).reduce(0, +) / CGFloat(row2.count)
                    return y1 > y2
                }

                // Within each row, sort blocks left-to-right and join
                let strings: [String] = rows.map { row in
                    let sorted = row.sorted { $0.minX < $1.minX }
                    return sorted.map(\.text).joined(separator: " ")
                }

                print("[OCR] Grouped into \(strings.count) lines")
                for (i, s) in strings.enumerated() {
                    print("[OCR] [\(i)] \(s)")
                }

                continuation.resume(returning: strings)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Convert UIImage.Orientation to CGImagePropertyOrientation
    private static func cgOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
