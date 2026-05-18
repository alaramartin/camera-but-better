import AVFoundation
import Photos

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Void, Error>) -> Void

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CaptureError.noData))
            return
        }
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
                } else {
                    self.completion(.success(()))
                }
            }
        }
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
