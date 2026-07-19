import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum PortraitEffect {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // CIDepthBlurEffect is far too slow to run per preview frame, so the live path
    // approximates it with a masked variable blur. The saved photo takes the real filter.
    static func apply(
        to image: CIImage,
        disparity: CIImage,
        range: ClosedRange<Float>,
        blurAmount: Float,
        subjectMask: CIImage?
    ) -> CIImage {
        guard blurAmount > 0 else { return image }

        let disparityExtent = disparity.extent
        guard disparityExtent.width > 0, disparityExtent.height > 0 else { return image }

        let scale = image.extent.width / disparityExtent.width

        // CIMaskedVariableBlur blurs in proportion to mask luminance, so the mask has to be
        // inverted disparity: the near subject has high disparity and must end up at 0 (sharp).
        // A subject is not a single depth plane — its sides and back sit below the peak
        // disparity — so the nearest band of the range is pinned to 0. The ramp past the band
        // is deliberately short: the filtered depth map smears the subject's disparity outward
        // across the silhouette too, and a long ramp would leave those smeared background
        // pixels near-sharp, drawing a sharp halo around the subject.
        let span = range.upperBound - range.lowerBound
        let focusFloor = range.upperBound - span * Constants.Portrait.focusBandFraction
        let rampSpan = span * Constants.Portrait.blurRampFraction
        let slope = CGFloat(-1 / rampSpan)
        let intercept = CGFloat(focusFloor / rampSpan)
        let mask = disparity
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
            // The color matrix's bias makes the extent infinite, and the upsample filter
            // answers an infinite inputSmallImage with an empty image — which downstream
            // reads as a zero mask, i.e. no blur anywhere.
            .cropped(to: disparityExtent)

        // The depth map cannot say where the silhouette is at pixel precision — its smoothing
        // straddles every edge — so the mask is upsampled guided by the frame itself, which
        // snaps the blur boundary onto the image's own edges. Blindly scaling the mask up
        // (Lanczos) is what left the outline a soft ramp.
        let upsampledMask = image
            .applyingFilter("CIEdgePreserveUpsampleFilter", parameters: [
                "inputSmallImage": mask
            ])
            .cropped(to: image.extent)

        // The mask is dark where the image must stay sharp, so a trace of local minimum
        // biases the snapped boundary just outside the silhouette, countering the blur
        // sampling subject pixels across it. Softening only antialiases that edge; grown past
        // a trace, either one re-draws a halo (sharp for erosion, blurred for softening).
        let erosion = CGFloat(Constants.Portrait.maskErosionDepthPixels) * scale
        let softening = CGFloat(Constants.Portrait.maskSofteningDepthPixels) * scale
        let refinedMask = upsampledMask
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: erosion])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: softening])
            .cropped(to: image.extent)
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])

        // Depth cannot say "this is all one object" — a tilted subject spans the disparity
        // range and its far side falls out of any focus band. Segmentation can, so wherever
        // it found subject the blur mask is forced to 0; depth still grades the rest.
        let blurMask = zeroingSubject(in: refinedMask, subjectMask: subjectMask, extent: image.extent)

        let longestSide = Float(max(image.extent.width, image.extent.height))
        let radius = max(
            Constants.Portrait.previewMinRadius,
            longestSide * Constants.Portrait.previewRadiusFraction
        ) * blurAmount

        return image
            .clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                "inputMask": blurMask.clampedToExtent(),
                kCIInputRadiusKey: radius
            ])
            .cropped(to: image.extent)
    }

    private static func zeroingSubject(in blurMask: CIImage, subjectMask: CIImage?, extent: CGRect) -> CIImage {
        guard let subjectMask,
              subjectMask.extent.width > 0, subjectMask.extent.height > 0
        else { return blurMask }
        let aligned = subjectMask.transformed(by: CGAffineTransform(
            scaleX: extent.width / subjectMask.extent.width,
            y: extent.height / subjectMask.extent.height
        ))
        let inverted = aligned.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
        ])
        return blurMask
            .applyingFilter("CIMultiplyBlendMode", parameters: [
                kCIInputBackgroundImageKey: inverted
            ])
            .cropped(to: extent)
    }

    enum CaptureError: LocalizedError {
        case decodeFailed
        case filterUnavailable
        case renderFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed: return "the captured image couldn't be decoded"
            case .filterUnavailable: return "CIDepthBlurEffect is unavailable"
            case .renderFailed: return "the depth blur failed to render"
            case .encodeFailed: return "the blurred image couldn't be re-encoded"
            }
        }
    }

    static func apply(
        toJPEG data: Data,
        depthData: AVDepthData,
        matte: AVPortraitEffectsMatte?,
        blurAmount: Float
    ) throws -> Data {
        guard blurAmount > 0 else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CaptureError.decodeFailed }

        // fileDataRepresentation() is unrotated sensor pixels plus an orientation tag, and
        // depthDataMap is unrotated too, so working here and re-attaching the tag on output
        // keeps the map registered to the pixels with no rotation math.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? CGImagePropertyOrientation.up.rawValue

        let input = CIImage(cgImage: cgImage)
        let disparityData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let disparityImage = CIImage(cvPixelBuffer: disparityData.depthDataMap)

        guard let filter = CIFilter(name: "CIDepthBlurEffect") else { throw CaptureError.filterUnavailable }
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
        // The segmentation matte, not the disparity, is what carries the silhouette at pixel
        // precision; with it the filter cuts the subject the way the system camera does. It
        // is unrotated sensor pixels like everything else here. Person-only — absent a
        // person the filter falls back to disparity edges.
        if let matte {
            filter.setValue(CIImage(cvPixelBuffer: matte.mattingImage), forKey: "inputMatteImage")
        }

        // Deliberately no Vision subject compositing here, only Apple's own pipeline: an
        // over-broad lifted mask once pasted the sharp original back over the whole frame and
        // silently erased the blur. The preview still uses segmentation; the capture trades
        // the tilted-subject nicety for a path that cannot un-blur itself.
        guard let output = filter.outputImage?.cropped(to: input.extent) else { throw CaptureError.renderFailed }

        guard let outputImage = context.createCGImage(output, from: output.extent) else { throw CaptureError.renderFailed }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CaptureError.encodeFailed }

        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: exifOrientation
        ]
        CGImageDestinationAddImage(destination, outputImage, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.encodeFailed }

        return outputData as Data
    }
}
