import SwiftUI

struct SessionPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let isRaw: Bool
    let videoURL: URL?
    let capturedAt: Date

    var isVideo: Bool { videoURL != nil }
}

@MainActor
final class SessionGalleryViewModel: ObservableObject {
    @Published var sessionPhotos: [SessionPhoto] = []

    func add(_ image: UIImage, isRaw: Bool, capturedAt: Date) {
        insert(SessionPhoto(image: image, isRaw: isRaw, videoURL: nil, capturedAt: capturedAt))
    }

    func add(videoThumbnail: UIImage, url: URL, capturedAt: Date) {
        insert(SessionPhoto(image: videoThumbnail, isRaw: false, videoURL: url, capturedAt: capturedAt))
    }

    // Items are added when their save finishes, which for video lags well behind a photo
    // taken during the same recording. Insert by capture time (newest first) so the grid
    // reads most-recent to oldest as it fills left-to-right, regardless of save order.
    private func insert(_ item: SessionPhoto) {
        if let index = sessionPhotos.firstIndex(where: { $0.capturedAt < item.capturedAt }) {
            sessionPhotos.insert(item, at: index)
        } else {
            sessionPhotos.append(item)
        }
    }
}
