import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum PortraitEffect {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // Preview and capture share this one renderer. Apple's CIDepthBlurEffect was tried for
    // captures across three sessions and never produced visible blur on device (its focus
    // selection with real calibration data is a black box), so the saved photo now takes the
    // exact pipeline the preview shows — the two match by construction.
    static func apply(
        to image: CIImage,
        disparity: CIImage,
        range: ClosedRange<Float>,
        blurAmount: Float,
        subjectMasks: [CIImage]
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
        var blurMask = refinedMask
        for subjectMask in subjectMasks {
            blurMask = zeroingSubject(in: blurMask, subjectMask: subjectMask, extent: image.extent)
        }

        let longestSide = Float(max(image.extent.width, image.extent.height))
        let radius = max(
            Constants.Portrait.blurMinRadius,
            longestSide * Constants.Portrait.blurRadiusFraction
        ) * blurAmount

        return image
            .clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                "inputMask": blurMask.clampedToExtent(),
                kCIInputRadiusKey: radius
            ])
            .cropped(to: image.extent)
    }

    private static func zeroingSubject(in blurMask: CIImage, subjectMask: CIImage, extent: CGRect) -> CIImage {
        guard subjectMask.extent.width > 0, subjectMask.extent.height > 0 else { return blurMask }
        let aligned = subjectMask.transformed(by: CGAffineTransform(
            scaleX: extent.width / subjectMask.extent.width,
            y: extent.height / subjectMask.extent.height
        ))
        // Feathered so the forced-sharp region antialiases into the blur instead of a hard
        // cutout; the fraction of image width keeps the edge matched between preview and
        // capture resolutions.
        let feather = extent.width * CGFloat(Constants.Portrait.subjectMaskFeatherFraction)
        let feathered = aligned
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: extent)
        let inverted = feathered.applyingFilter("CIColorMatrix", parameters: [
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
        case flatDepth
        case renderFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed: return "the captured image couldn't be decoded"
            case .flatDepth: return "the scene has no usable depth separation"
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
        let disparityMap = disparityData.depthDataMap
        guard let range = DisparityStatistics.percentileRange(of: disparityMap),
              range.upperBound - range.lowerBound >= Constants.Portrait.minDisparitySpan
        else { throw CaptureError.flatDepth }

        // Both masks only ever force blur to zero inside a bounded region — unlike the old
        // CIBlendWithMask composite, which pasted the sharp original over the frame and once
        // silently erased the blur. The Vision mask is additionally nearest-instance-only and
        // coverage-guarded before it gets here.
        var subjectMasks: [CIImage] = []
        if let matte {
            subjectMasks.append(CIImage(cvPixelBuffer: matte.mattingImage, options: [.colorSpace: NSNull()]))
        }
        if let lifted = SubjectMaskProvider.mask(forCGImage: cgImage, disparity: disparityMap) {
            subjectMasks.append(lifted)
        }

        // NSNull on the disparity opts out of color management: the floats are data, and
        // sRGB-decoding them would desynchronise the map from the CPU-measured range.
        let output = apply(
            to: input,
            disparity: CIImage(cvPixelBuffer: disparityMap, options: [.colorSpace: NSNull()]),
            range: range,
            blurAmount: blurAmount,
            subjectMasks: subjectMasks
        )

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
