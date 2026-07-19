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
        let matte = photo.portraitEffectsMatte
        // The depth blur is far heavier than bloom, and this is the photo output's own queue,
        // so keeping the chain here would stall subsequent captures.
        DispatchQueue.global(qos: .userInitiated).async {
            self.process(originalData, depthData: depthData, matte: matte)
        }
    }

    private func process(_ originalData: Data, depthData: AVDepthData?, matte: AVPortraitEffectsMatte?) {
        var data = originalData
        // Portrait, bloom and cropping all demosaic into a processed image, which defeats
        // ProRAW, so they are JPEG-only. Portrait runs before the crop because the depth map
        // covers the full uncropped frame and would otherwise misregister.
        // A portrait failure must not lose the shot: the unblurred photo still saves, and the
        // reason surfaces through the capture alert instead of vanishing into a fallback.
        var portraitProblem: String?
        if portraitBlurAmount > 0, !isRaw {
            if let depthData {
                do {
                    data = try PortraitEffect.apply(toJPEG: data, depthData: depthData, matte: matte, blurAmount: portraitBlurAmount)
                } catch {
                    portraitProblem = error.localizedDescription
                }
            } else {
                portraitProblem = "the capture carried no depth data"
            }
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
                } else if let portraitProblem {
                    self.completion(.failure(CaptureError.portraitNotApplied(portraitProblem)))
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
        case portraitNotApplied(String)

        var errorDescription: String? {
            switch self {
            case .noData: return "Failed to get photo data from the camera."
            case .photoLibraryDenied: return "Photo library access denied. Enable it in Settings."
            case .portraitNotApplied(let reason): return "Photo saved, but without portrait blur: \(reason)."
            }
        }
    }
}
