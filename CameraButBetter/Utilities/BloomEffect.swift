import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum BloomEffect {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }

        // Real bloom: isolate the pixels brighter than a threshold, blur only those into a
        // glow, and add the glow back over the untouched original. CIBloom by contrast just
        // soft-blurs the whole frame, which reads as a flat white haze rather than light
        // bleeding out of highlights.
        let threshold = Constants.Bloom.threshold

        let highlights = image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: CGFloat(-threshold), y: CGFloat(-threshold), z: CGFloat(-threshold), w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])

        // A fixed pixel radius reads very differently between the small preview buffer and
        // the full-resolution capture, so scale it to the image so both look the same.
        let longestSide = Float(max(image.extent.width, image.extent.height))
        let radius = max(Constants.Bloom.minRadius, longestSide * Constants.Bloom.radiusFraction)
        let glowGain = CGFloat(intensity * Constants.Bloom.gain)

        let glow = highlights
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: image.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: glowGain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: glowGain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: glowGain, w: 0)
            ])

        return glow
            .applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": image])
            .cropped(to: image.extent)
    }

    static func apply(toJPEG data: Data, intensity: Float) -> Data? {
        guard intensity > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? CGImagePropertyOrientation.up.rawValue

        let bloomed = apply(to: CIImage(cgImage: cgImage), intensity: intensity)
        guard let outputImage = context.createCGImage(bloomed, from: bloomed.extent) else { return nil }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: exifOrientation
        ]
        CGImageDestinationAddImage(destination, outputImage, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return outputData as Data
    }
}
