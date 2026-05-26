import AVFoundation
import ImageIO
import Photos
import UIKit

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void
    private let aspectRatio: PreviewAspectRatio

    init(aspectRatio: PreviewAspectRatio, completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.aspectRatio = aspectRatio
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
        let data = PhotoCropper.crop(originalData, to: aspectRatio) ?? originalData
        let thumbnail = Self.thumbnail(from: data)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.completion(.failure(CaptureError.photoLibraryDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
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
