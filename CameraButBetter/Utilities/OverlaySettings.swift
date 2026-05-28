import SwiftUI

enum PhotoFormat: String, CaseIterable, Identifiable {
    case jpeg
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .raw: return "RAW"
        }
    }
}

final class OverlaySettings: ObservableObject {
    private enum Key {
        static let level = "overlay.level"
        static let grid = "overlay.grid"
        static let centerCross = "overlay.centerCross"
        static let aspectRatio = "composition.aspectRatio"
        static let photoFormat = "capture.photoFormat"
    }

    @Published var showLevel: Bool {
        didSet { UserDefaults.standard.set(showLevel, forKey: Key.level) }
    }

    @Published var showGrid: Bool {
        didSet { UserDefaults.standard.set(showGrid, forKey: Key.grid) }
    }

    @Published var showCenterCross: Bool {
        didSet { UserDefaults.standard.set(showCenterCross, forKey: Key.centerCross) }
    }

    @Published var aspectRatio: PreviewAspectRatio {
        didSet { UserDefaults.standard.set(aspectRatio.rawValue, forKey: Key.aspectRatio) }
    }

    @Published var photoFormat: PhotoFormat {
        didSet { UserDefaults.standard.set(photoFormat.rawValue, forKey: Key.photoFormat) }
    }

    init() {
        let defaults = UserDefaults.standard
        showLevel = defaults.bool(forKey: Key.level)
        showGrid = defaults.bool(forKey: Key.grid)
        showCenterCross = defaults.bool(forKey: Key.centerCross)
        aspectRatio = defaults.string(forKey: Key.aspectRatio)
            .flatMap(PreviewAspectRatio.init(rawValue:)) ?? .fourThree
        photoFormat = defaults.string(forKey: Key.photoFormat)
            .flatMap(PhotoFormat.init(rawValue:)) ?? .jpeg
    }
}
