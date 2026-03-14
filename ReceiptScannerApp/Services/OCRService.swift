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

                // Sort observations top-to-bottom based on bounding box
                let sorted = observations.sorted { a, b in
                    a.boundingBox.origin.y > b.boundingBox.origin.y
                }

                let strings = sorted.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                print("[OCR] Recognized \(strings.count) lines")
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
