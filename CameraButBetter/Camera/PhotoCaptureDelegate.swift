import AVFoundation
import ImageIO
import Photos
import UIKit

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void
    private let aspectRatio: PreviewAspectRatio
    private let isRaw: Bool
    private let bloomIntensity: Float
    private let portraitBlurAmount: Float

    init(
        aspectRatio: PreviewAspectRatio,
        isRaw: Bool,
        bloomIntensity: Float,
        portraitBlurAmount: Float,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        self.aspectRatio = aspectRatio
        self.isRaw = isRaw
        self.bloomIntensity = bloomIntensity
        self.portraitBlurAmount = portraitBlurAmount
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let originalData = photo.fileDataRepresentation() else {
            completion(.failure(CaptureError.noData))
            return
        }
        let depthData = photo.depthData
        // The depth blur is far heavier than bloom, and this is the photo output's own queue,
        // so keeping the chain here would stall subsequent captures.
        DispatchQueue.global(qos: .userInitiated).async {
            self.process(originalData, depthData: depthData)
        }
    }

    private func process(_ originalData: Data, depthData: AVDepthData?) {
        var data = originalData
        // Portrait, bloom and cropping all demosaic into a processed image, which defeats
        // ProRAW, so they are JPEG-only. Portrait runs before the crop because the depth map
        // covers the full uncropped frame and would otherwise misregister.
        if portraitBlurAmount > 0, !isRaw, let depthData {
            data = PortraitEffect.apply(toJPEG: data, depthData: depthData, blurAmount: portraitBlurAmount) ?? data
        }
        if !isRaw {
            data = PhotoCropper.crop(data, to: aspectRatio) ?? data
        }
        if bloomIntensity > 0, !isRaw {
            data = BloomEffect.apply(toJPEG: data, intensity: bloomIntensity) ?? data
        }
        let saved = data
        let thumbnail = Self.thumbnail(from: saved)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.completion(.failure(CaptureError.photoLibraryDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: saved, options: nil)
            } completionHandler: { _, saveError in
                if let saveError {
                    self.completion(.failure(saveError))
                } else if let thumbnail {
                    self.completion(.success(thumbnail))
                } else {
                    self.completion(.failure(CaptureError.noData))
                }
            }
        }
    }

    private static func thumbnail(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return UIImage(data: data) }
        return UIImage(cgImage: cgImage)
    }

    enum CaptureError: LocalizedError {
        case noData
        case photoLibraryDenied

        var errorDescription: String? {
            switch self {
            case .noData: return "Failed to get photo data from the camera."
            case .photoLibraryDenied: return "Photo library access denied. Enable it in Settings."
            }
        }
    }
}
