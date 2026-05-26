import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum PhotoCropper {
    static func crop(_ data: Data, to ratio: PreviewAspectRatio) -> Data? {
        guard ratio != .fourThree else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // The portrait ratio (width/height) the user sees must be matched against the
        // display-oriented dimensions, which swap for orientations that rotate 90 degrees.
        let isQuarterTurn: Bool
        switch exifOrientation {
        case .left, .right, .leftMirrored, .rightMirrored: isQuarterTurn = true
        default: isQuarterTurn = false
        }
        let displayWidth = isQuarterTurn ? pixelHeight : pixelWidth
        let displayHeight = isQuarterTurn ? pixelWidth : pixelHeight

        let targetRatio = ratio.portraitRatio
        var cropDisplayWidth = displayWidth
        var cropDisplayHeight = displayWidth / targetRatio
        if cropDisplayHeight > displayHeight {
            cropDisplayHeight = displayHeight
            cropDisplayWidth = displayHeight * targetRatio
        }

        // Map the centered display-space crop rect into the image's native pixel space.
        let cropPixelWidth = isQuarterTurn ? cropDisplayHeight : cropDisplayWidth
        let cropPixelHeight = isQuarterTurn ? cropDisplayWidth : cropDisplayHeight
        let cropRect = CGRect(
            x: ((pixelWidth - cropPixelWidth) / 2).rounded(),
            y: ((pixelHeight - cropPixelHeight) / 2).rounded(),
            width: cropPixelWidth.rounded(),
            height: cropPixelHeight.rounded()
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: exifOrientation.rawValue
        ]
        CGImageDestinationAddImage(destination, cropped, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return outputData as Data
    }
}
