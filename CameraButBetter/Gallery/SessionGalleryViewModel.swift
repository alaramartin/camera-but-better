import SwiftUI

struct SessionPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let isRaw: Bool
    let videoURL: URL?

    var isVideo: Bool { videoURL != nil }
}

@MainActor
final class SessionGalleryViewModel: ObservableObject {
    @Published var sessionPhotos: [SessionPhoto] = []

    func add(_ image: UIImage, isRaw: Bool) {
        sessionPhotos.append(SessionPhoto(image: image, isRaw: isRaw, videoURL: nil))
    }

    func add(videoThumbnail: UIImage, url: URL) {
        sessionPhotos.append(SessionPhoto(image: videoThumbnail, isRaw: false, videoURL: url))
    }
}
