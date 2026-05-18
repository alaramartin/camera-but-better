import SwiftUI

@MainActor
final class SessionGalleryViewModel: ObservableObject {
    @Published var sessionPhotos: [UIImage] = []

    func add(_ photo: UIImage) {
        sessionPhotos.append(photo)
    }
}
