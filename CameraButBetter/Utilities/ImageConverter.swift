import AVFoundation
import CoreImage
import UIKit

enum ImageConverter {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let maxDimension: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.7

    static func base64JPEG(from sampleBuffer: CMSampleBuffer, aspectRatio: PreviewAspectRatio) -> String? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // The buffer is sensor-native landscape; a portrait frame ratio w/h maps to a
        // landscape crop aspect of its reciprocal so the AI sees the same composition.
        let cropped = centerCrop(ciImage, toAspect: 1 / aspectRatio.portraitRatio)
        let scaled = scaledToFit(cropped, maxDimension: maxDimension)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: jpegQuality) else { return nil }
        return data.base64EncodedString()
    }

    private static func centerCrop(_ image: CIImage, toAspect aspect: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, aspect > 0 else { return image }
        var cropWidth = extent.width
        var cropHeight = cropWidth / aspect
        if cropHeight > extent.height {
            cropHeight = extent.height
            cropWidth = cropHeight * aspect
        }
        let rect = CGRect(
            x: extent.origin.x + (extent.width - cropWidth) / 2,
            y: extent.origin.y + (extent.height - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        )
        return image.cropped(to: rect)
    }

    private static func scaledToFit(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
