import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision

final class OCRService {
  private let maximumImageDimension: CGFloat

  init(maximumImageDimension: CGFloat = 2_200) {
    self.maximumImageDimension = maximumImageDimension
  }

  func extractText(
    from image: UIImage,
    preferredLanguages: [String] = []
  ) async throws -> String {
    let orientation = image.cgImageOrientation
    let maximumImageDimension = self.maximumImageDimension

    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let sourceImage = try Self.makeCGImage(from: image)
          let preparedImage = Self.downsample(
            sourceImage,
            maximumDimension: maximumImageDimension
          )

          let request = VNRecognizeTextRequest { request, error in
            if let error = error {
              continuation.resume(throwing: error)
              return
            }

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let text = Self.orderedText(from: observations)

            guard !text.isEmpty else {
              continuation.resume(throwing: OCRServiceError.noTextRecognized)
              return
            }

            continuation.resume(returning: text)
          }

          request.recognitionLevel = .accurate
          request.usesLanguageCorrection = true
          request.minimumTextHeight = 0.008

          if let supportedLanguages = try? request.supportedRecognitionLanguages() {
            let selectedLanguages = preferredLanguages.filter {
              supportedLanguages.contains($0)
            }

            if !selectedLanguages.isEmpty {
              request.recognitionLanguages = selectedLanguages
            }
          }

          let handler = VNImageRequestHandler(
            cgImage: preparedImage,
            orientation: orientation,
            options: [:]
          )

          try handler.perform([request])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func makeCGImage(from image: UIImage) throws -> CGImage {
    if let cgImage = image.cgImage {
      return cgImage
    }

    if let ciImage = image.ciImage {
      let context = CIContext(options: nil)
      if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
        return cgImage
      }
    }

    throw OCRServiceError.invalidImage
  }

  private static func downsample(
    _ image: CGImage,
    maximumDimension: CGFloat
  ) -> CGImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let longestSide = max(width, height)

    guard longestSide > maximumDimension, maximumDimension > 0 else {
      return image
    }

    let scale = maximumDimension / longestSide
    let targetWidth = max(Int((width * scale).rounded()), 1)
    let targetHeight = max(Int((height * scale).rounded()), 1)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return image
    }

    context.interpolationQuality = .high
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    )

    return context.makeImage() ?? image
  }

  private static func orderedText(
    from observations: [VNRecognizedTextObservation]
  ) -> String {
    let sorted = observations.sorted { first, second in
      let verticalDifference = abs(first.boundingBox.midY - second.boundingBox.midY)

      if verticalDifference > 0.015 {
        return first.boundingBox.midY > second.boundingBox.midY
      }

      return first.boundingBox.minX < second.boundingBox.minX
    }

    return
      sorted
      .compactMap { $0.topCandidates(1).first?.string }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }
}

enum OCRServiceError: LocalizedError {
  case invalidImage
  case noTextRecognized

  var errorDescription: String? {
    switch self {
    case .invalidImage:
      return "Kuvaa ei voitu käsitellä."
    case .noTextRecognized:
      return "Kuvasta ei löytynyt luettavaa tekstiä."
    }
  }
}

extension UIImage {
  fileprivate var cgImageOrientation: CGImagePropertyOrientation {
    switch imageOrientation {
    case .up:
      return .up
    case .down:
      return .down
    case .left:
      return .left
    case .right:
      return .right
    case .upMirrored:
      return .upMirrored
    case .downMirrored:
      return .downMirrored
    case .leftMirrored:
      return .leftMirrored
    case .rightMirrored:
      return .rightMirrored
    @unknown default:
      return .up
    }
  }
}
