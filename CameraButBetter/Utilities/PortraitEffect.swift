import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum PortraitEffect {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // CIDepthBlurEffect is far too slow to run per preview frame, so the live path
    // approximates it with a masked variable blur. The saved photo takes the real filter.
    static func apply(to image: CIImage, disparity: CIImage, range: ClosedRange<Float>, blurAmount: Float) -> CIImage {
        guard blurAmount > 0 else { return image }

        let disparityExtent = disparity.extent
        guard disparityExtent.width > 0, disparityExtent.height > 0 else { return image }

        let scale = image.extent.width / disparityExtent.width
        let aspect = (image.extent.height / disparityExtent.height) / scale
        // Nearest-neighbour upscaling of a ~320x240 map to full frame gives visibly blocky
        // bokeh edges; Lanczos keeps the subject outline smooth.
        let upscaled = disparity
            .clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: aspect
            ])
            .cropped(to: image.extent)

        // CIMaskedVariableBlur blurs in proportion to mask luminance, so the mask has to be
        // inverted disparity: the near subject has high disparity and must end up at 0 (sharp).
        // A subject is not a single depth plane — its sides and back sit below the peak
        // disparity, as does the ramp the filtered depth map smears along its silhouette — so
        // the nearest band of the range is pinned to 0 and the blur ramp is normalised over
        // only the remaining background span.
        let span = range.upperBound - range.lowerBound
        let focusFloor = range.upperBound - span * Constants.Portrait.focusBandFraction
        let backgroundSpan = focusFloor - range.lowerBound
        let slope = CGFloat(-1 / backgroundSpan)
        let intercept = CGFloat(focusFloor / backgroundSpan)
        let mask = upscaled
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: slope, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: slope, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: slope, w: 0),
                "inputBiasVector": CIVector(x: intercept, y: intercept, z: intercept, w: 1)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])

        // The mask is dark where the image must stay sharp, so taking the local minimum grows
        // the sharp region and retreats the blur off the subject's outline. Softening
        // afterwards hides the stair-stepping the low-resolution map would otherwise show,
        // and lands in the background where it is harmless.
        let erosion = CGFloat(Constants.Portrait.maskErosionDepthPixels) * scale
        let softening = CGFloat(Constants.Portrait.maskSofteningDepthPixels) * scale
        let refinedMask = mask
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: erosion])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: softening])
            .cropped(to: image.extent)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])

        let longestSide = Float(max(image.extent.width, image.extent.height))
        let radius = max(
            Constants.Portrait.previewMinRadius,
            longestSide * Constants.Portrait.previewRadiusFraction
        ) * blurAmount

        return image
            .clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                "inputMask": refinedMask.clampedToExtent(),
                kCIInputRadiusKey: radius
            ])
            .cropped(to: image.extent)
    }

    static func apply(toJPEG data: Data, depthData: AVDepthData, blurAmount: Float) -> Data? {
        guard blurAmount > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        // fileDataRepresentation() is unrotated sensor pixels plus an orientation tag, and
        // depthDataMap is unrotated too, so working here and re-attaching the tag on output
        // keeps the map registered to the pixels with no rotation math.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? CGImagePropertyOrientation.up.rawValue

        let input = CIImage(cgImage: cgImage)
        let disparityData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let disparityImage = CIImage(cvPixelBuffer: disparityData.depthDataMap)

        guard let filter = CIFilter(name: "CIDepthBlurEffect") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(disparityImage, forKey: "inputDisparityImage")
        // inputAperture is not an f-number: it runs 0...22 with higher meaning more blur,
        // which is the opposite of a lens, so it tracks blurAmount rather than the f-stop.
        filter.setValue(Constants.Portrait.coreImageApertureMax * blurAmount, forKey: "inputAperture")
        // inputScaleFactor is not the image-to-disparity ratio (the filter registers the
        // disparity map itself); it declares how far the input image is downscaled from the
        // original capture, so anything above 1 inflates the blur kernel until it floods
        // across depth edges. Full-resolution input means 1.
        filter.setValue(1.0, forKey: "inputScaleFactor")
        if let calibration = disparityData.cameraCalibrationData {
            filter.setValue(calibration, forKey: "inputCalibrationData")
        }

        guard let output = filter.outputImage?.cropped(to: input.extent),
              let outputImage = context.createCGImage(output, from: output.extent)
        else { return nil }

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
