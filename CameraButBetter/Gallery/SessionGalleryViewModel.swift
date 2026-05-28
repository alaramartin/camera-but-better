import SwiftUI

struct SessionPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let isRaw: Bool
}

@MainActor
final class SessionGalleryViewModel: ObservableObject {
    @Published var sessionPhotos: [SessionPhoto] = []

    func add(_ image: UIImage, isRaw: Bool) {
        sessionPhotos.append(SessionPhoto(image: image, isRaw: isRaw))
    }
}
